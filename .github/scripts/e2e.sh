#!/bin/bash
#
# e2e.sh <package.tgz | package-spec> <work-dir>
#
# End-to-end check of @nemtus/symbol-bootstrap, the way users install it:
#   1. `npm install -g <package>` and resolve the `symbol-bootstrap` command from PATH;
#   2. `symbol-bootstrap --version` reports the NEMTUS package (and EXPECTED_VERSION, when set);
#   3. `symbol-bootstrap start -p bootstrap` runs a full local network (upstream Docker images, Docker
#      Compose V2) detached, with the built-in health check;
#   4. the REST gateway answers and the chain height grows past the nemesis block;
#   5. the network is stopped and cleaned.
# <package> is a packed tarball (CI) or a registry spec such as @nemtus/symbol-bootstrap@1.1.13 (the
# post-publish check). Runs from <work-dir> (outside the repo) so nothing resolves against a checkout.
# Set NPM_CONFIG_PREFIX to install into a throwaway prefix instead of the global one.

set -euo pipefail

PACKAGE="${1:?usage: e2e.sh <package.tgz | package-spec> <work-dir>}"
WORK="${2:?usage: e2e.sh <package.tgz | package-spec> <work-dir>}"
REST="${REST_URL:-http://localhost:3000}"

if [ -f "$PACKAGE" ]; then
	PACKAGE="$(realpath "$PACKAGE")"
	EXPECTED_VERSION="${EXPECTED_VERSION:-$(tar -xOzf "$PACKAGE" package/package.json \
		| node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0)).version)')}"
fi

mkdir -p "$WORK"
cd "$WORK"
# Relative on purpose: symbol-bootstrap resolves -t against the current directory (an absolute path
# gets the working directory prefixed a second time).
TARGET=target

echo "::group::npm install -g ${PACKAGE##*/}"
npm install -g "$PACKAGE"
if [ -n "${NPM_CONFIG_PREFIX:-}" ]; then export PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"; fi
echo '::endgroup::'

echo "symbol-bootstrap resolved to $(command -v symbol-bootstrap)"
REPORTED="$(symbol-bootstrap --version)"
echo "symbol-bootstrap --version: ${REPORTED}"
case "$REPORTED" in
	"@nemtus/symbol-bootstrap/${EXPECTED_VERSION:-}"*) ;;
	*) echo "::error::expected '@nemtus/symbol-bootstrap/${EXPECTED_VERSION:-<any>} ...', got '${REPORTED}'"; exit 1 ;;
esac

cleanup() {
	symbol-bootstrap stop -t "$TARGET" || true
	# `stop` leaves the containers and network behind; remove them so local runs leave no residue.
	docker compose -f "$TARGET/docker/docker-compose.yml" down --remove-orphans || true
	symbol-bootstrap clean -t "$TARGET" || true
}
trap cleanup EXIT

echo "::group::symbol-bootstrap start -p bootstrap"
symbol-bootstrap start -p bootstrap -t "$TARGET" --noPassword --detached --healthCheck
echo '::endgroup::'

height() { curl -fsS "${REST}/chain/info" | node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0)).height))'; }

for _ in $(seq 1 60); do
	h="$(height 2>/dev/null || echo 0)"
	echo "chain height: ${h}"
	if [ "${h}" -ge 3 ]; then
		echo "local network is producing blocks (height ${h})"
		exit 0
	fi
	sleep 5
done
echo "::error::chain height did not reach 3 within 5 minutes"
exit 1
