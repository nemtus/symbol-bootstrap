#!/bin/bash
#
# check-version-map.sh [--release]
#
# Validates the NEMTUS version map in docs/nemtus-fork.md — the table that says which upstream
# release and which Docker images each @nemtus/symbol-bootstrap release is built from. NEMTUS and
# upstream version numbers diverge (a NEMTUS-only fix takes the next patch number, so NEMTUS 1.1.14 is
# NOT upstream v1.1.14); the table is the single place that records the mapping.
#
# Two modes, on purpose:
#
#   default    Structural checks only (table present, rows well-formed, versions unique and
#              descending). Row-level findings for the current package.json version are printed as
#              notices and never fail. This is what the `parity` CI job runs on every PR.
#              It MUST stay non-blocking for row-level findings: between releases `dev` legitimately
#              differs from the last released row (an upstream sync PR bumps the images, or even the
#              version, before anyone has written the next row), and failing there would block the
#              automated sync PRs.
#
#   --release  Additionally requires a row for the package.json version whose tag, upstream base and
#              image columns match the tree. publish.yml runs this on the release tag, so a release
#              cannot be published without its row. Run it locally on the release PR branch too.
#
# What "match the tree" means:
#   - Git tag column        == nemtus-v<package.json version>
#   - Upstream base column  == v<newest version heading in upstream's CHANGELOG.md>
#   - symbol-server column  == tag of symbolServerImage in presets/shared.yml
#   - symbol-rest column    == tag of symbolRestImage in presets/shared.yml
#
# Usage: bash .github/scripts/check-version-map.sh [--release]   (from anywhere inside the repo)

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 2

DOC='docs/nemtus-fork.md'
START='<!-- nemtus-version-map:start -->'
END='<!-- nemtus-version-map:end -->'
TAG_PREFIX='nemtus-v'

release=0
case "${1:-}" in
'') ;;
--release) release=1 ;;
*)
	echo "usage: check-version-map.sh [--release]" >&2
	exit 2
	;;
esac

failures=0
fail() {
	printf 'FAIL %s\n' "$1"
	failures=$((failures + 1))
}
pass() { printf 'ok   %s\n' "$1"; }
# Row-level finding: an error in --release mode, a (GitHub Actions) notice otherwise.
finding() {
	if [ "$release" = 1 ]; then
		fail "$1"
	elif [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "::notice title=NEMTUS version map::$1"
	else
		printf 'note %s\n' "$1"
	fi
}

# Data rows between the markers, as `version|tag|released|upstream|server|rest` with the markdown
# decoration (spaces, backticks) removed. The header and the |---| separator are skipped.
rows="$(awk -v start="$START" -v end="$END" '
	index($0, start) { inside = 1; next }
	index($0, end) { inside = 0 }
	inside && /^\|/ {
		n = split($0, cell, "|")
		for (i = 2; i <= 7; i++) { gsub(/[ `]/, "", cell[i]) }
		if (cell[2] !~ /^[0-9]/) next
		print cell[2] "|" cell[3] "|" cell[4] "|" cell[5] "|" cell[6] "|" cell[7]
	}' "$DOC")"

if ! grep -qF "$START" "$DOC" || ! grep -qF "$END" "$DOC"; then
	fail "${DOC} has the version map markers (${START} ... ${END})"
elif [ -z "$rows" ]; then
	fail "${DOC} version map has at least one release row"
else
	pass "${DOC} has a version map ($(wc -l <<<"$rows" | tr -d ' ') release rows)"
fi

if [ -n "$rows" ]; then
	malformed="$(grep -vE '^[0-9]+\.[0-9]+\.[0-9]+\|nemtus-v[0-9]+\.[0-9]+\.[0-9]+\|[0-9]{4}-[0-9]{2}-[0-9]{2}\|v[0-9]+\.[0-9]+\.[0-9]+\|[^|]+\|[^|]+$' <<<"$rows" || true)"
	if [ -z "$malformed" ]; then
		pass "every row is <x.y.z> | nemtus-v<x.y.z> | <YYYY-MM-DD> | v<x.y.z> | <server tag> | <rest tag>"
	else
		fail "malformed version map row(s): $(tr '\n' ' ' <<<"$malformed")"
	fi

	versions="$(cut -d'|' -f1 <<<"$rows")"
	if [ "$versions" = "$(sort -u -V -r <<<"$versions")" ]; then
		pass "release rows are unique and newest first"
	else
		fail "version map rows must be unique and sorted newest first"
	fi

	mismatched_tags="$(awk -F'|' -v prefix="$TAG_PREFIX" '$2 != prefix $1 { print $1 }' <<<"$rows")"
	if [ -z "$mismatched_tags" ]; then
		pass "every row's Git tag is ${TAG_PREFIX}<version>"
	else
		fail "Git tag column does not match the version in row(s): $(tr '\n' ' ' <<<"$mismatched_tags")"
	fi
fi

# --- row for the version in package.json ------------------------------------------------------------
VERSION="$(node -p 'require("./package.json").version')"
image_tag() { sed -n -E "s/^$1:[[:space:]]*[^[:space:]]+:([^[:space:]:]+)[[:space:]]*\$/\\1/p" presets/shared.yml | head -n 1; }
tree_server="$(image_tag symbolServerImage)"
tree_rest="$(image_tag symbolRestImage)"
# Upstream's CHANGELOG.md is upstream-owned and its newest heading is the upstream release merged here.
tree_upstream="$(grep -m 1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | tr -d '# []')"

row="$(grep -m 1 -E "^${VERSION//./\\.}\|" <<<"$rows" || true)"
if [ -z "$row" ]; then
	finding "no version map row for ${VERSION} (package.json): add one to ${DOC} before releasing (upstream v${tree_upstream:-?}, symbol-server ${tree_server:-?}, symbol-rest ${tree_rest:-?})"
else
	IFS='|' read -r _ _ _ row_upstream row_server row_rest <<<"$row"
	before="$failures"
	if [ -z "$tree_upstream" ]; then
		# Upstream changed its changelog format: not something a release should be blocked on.
		echo "note could not read the newest upstream version from CHANGELOG.md; upstream base of ${VERSION} not checked"
	elif [ "$row_upstream" != "v${tree_upstream}" ]; then
		finding "version map row ${VERSION} says upstream ${row_upstream}, but this tree contains upstream v${tree_upstream}"
	fi
	[ "$row_server" = "$tree_server" ] ||
		finding "version map row ${VERSION} says symbol-server ${row_server}, but presets/shared.yml pins ${tree_server:-?}"
	[ "$row_rest" = "$tree_rest" ] ||
		finding "version map row ${VERSION} says symbol-rest ${row_rest}, but presets/shared.yml pins ${tree_rest:-?}"
	if [ "$release" = 1 ] && [ "$failures" = "$before" ]; then
		pass "version map row ${VERSION} matches the tree (upstream ${row_upstream}, symbol-server ${row_server}, symbol-rest ${row_rest})"
	fi
fi

if [ "$failures" -ne 0 ]; then
	echo "${failures} version map check(s) FAILED — see docs/nemtus-fork.md (Versioning)"
	exit 1
fi
echo "version map checks passed"
