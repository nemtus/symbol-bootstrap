#!/bin/bash
#
# check-nemtus-mirror-invariants.sh
#
# Asserts the NEMTUS fork layer of nemtus/symbol-bootstrap is intact. An upstream merge can silently
# revert any of these (e.g. upstream editing a line next to a NEMTUS edit and the merge being resolved
# in upstream's favour), so the `parity` CI job runs this on every PR, including automated sync PRs.
# See docs/nemtus-fork.md.
#
# Usage: bash .github/scripts/check-nemtus-mirror-invariants.sh   (from anywhere inside the repo)

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 2

PACKAGE='@nemtus/symbol-bootstrap'
BIN='symbol-bootstrap'
failures=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { # check <description> <command...>
	local description="$1"
	shift
	if "$@" >/dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}
# json <file> <js expression over `o`>: prints the value (Node.js is this repo's toolchain; no jq needed).
json() {
	node -e 'const o = require(require("path").resolve(process.argv[1])); const v = eval(process.argv[2]);
		if (v === undefined || v === null) process.exit(1); console.log(typeof v === "object" ? JSON.stringify(v) : String(v));' "$1" "$2"
}

# 1. Package identity: published under the NEMTUS scope, CLI name unchanged (drop-in for upstream docs).
check "package.json name is ${PACKAGE}" test "$(json package.json o.name)" = "$PACKAGE"
check "package.json repository points at nemtus/symbol-bootstrap" \
	test "$(json package.json 'typeof o.repository === "object" ? o.repository.url : o.repository')" = 'github:nemtus/symbol-bootstrap'
check "package.json bugs points at nemtus" test "$(json package.json o.bugs)" = 'https://github.com/nemtus/symbol-bootstrap/issues'
check "package.json homepage points at nemtus" test "$(json package.json o.homepage)" = 'https://github.com/nemtus/symbol-bootstrap#readme'
check "package.json publishConfig is public with provenance" \
	test "$(json package.json '`${o.publishConfig.access} ${o.publishConfig.provenance}`')" = 'public true'
check "bin is still '${BIN}'" test "$(json package.json "o.bin['${BIN}']")" = 'bin/run'
check "oclif.bin is still '${BIN}'" test "$(json package.json o.oclif.bin)" = "$BIN"
check "engines.node requires Node.js 24+" test "$(json package.json o.engines.node)" = '>=24.0.0'

# 2. Lockfile agrees with package.json (a sync that resolves only one of the two would break `npm ci`).
VERSION="$(json package.json o.version)"
check "package-lock.json root name/version match package.json" \
	test "$(json package-lock.json '`${o.name} ${o.version}`')" = "${PACKAGE} ${VERSION}"
check "package-lock.json packages[\"\"] name/version match package.json" \
	test "$(json package-lock.json '`${o.packages[""].name} ${o.packages[""].version}`')" = "${PACKAGE} ${VERSION}"

# 3. Upstream's publish/CI workflows stay removed (they publish the unscoped package with NPM_TOKEN
#    and use unpinned actions). An upstream edit to one of them shows up as a modify/delete conflict.
for wf in build.yml alpha.yml release.yml; do
	check "upstream workflow .github/workflows/${wf} is absent" test ! -e ".github/workflows/${wf}"
done
check "no workflow uses an NPM_TOKEN secret (publishing is OIDC Trusted Publishing)" \
	bash -c "! grep -rq 'secrets.NPM_TOKEN' .github/workflows"

# 4. Every third-party action is pinned to a full commit SHA.
unpinned="$(grep -rhoE '^\s*-?\s*uses:\s*[^ #]+' .github/workflows 2>/dev/null \
	| sed -E 's/^\s*-?\s*uses:\s*//' \
	| grep -v '^\./' \
	| grep -vE '@[0-9a-f]{40}$' || true)"
if [ -z "$unpinned" ]; then pass "all workflow actions are SHA-pinned"; else fail "unpinned actions: $(tr '\n' ' ' <<<"$unpinned")"; fi

# 5. Docker Compose V2 support (NEMTUS patch): no hardcoded `docker-compose` spawn.
check "RuntimeService resolves the Docker Compose command" grep -q 'getDockerComposeCommand' src/service/RuntimeService.ts
check "RunService uses the resolved Docker Compose command" grep -q 'getDockerComposeCommand' src/service/RunService.ts
check "RunService does not spawn a hardcoded docker-compose" \
	bash -c "! grep -q \"command: 'docker-compose'\" src/service/RunService.ts"
check "VerifyService does not check a hardcoded docker-compose" \
	bash -c "! grep -q \"'docker-compose --version'\" src/service/VerifyService.ts"

# 6. The README tells users which package this is.
check "README.md carries the NEMTUS fork notice" grep -q '<!-- nemtus-mirror-notice -->' README.md

# 7. The NEMTUS version map (docs/nemtus-fork.md) is well-formed. Structure only: whether the row of
#    the current version matches the tree is enforced at release time (check-version-map.sh --release,
#    run by publish.yml), not here — a sync PR is legitimately ahead of the last released row.
if bash .github/scripts/check-version-map.sh; then
	pass "NEMTUS version map is well-formed"
else
	fail "NEMTUS version map is well-formed (see the output above)"
fi

if [ "$failures" -ne 0 ]; then
	echo "${failures} invariant(s) FAILED — see docs/nemtus-fork.md"
	exit 1
fi
echo "all checks passed"
