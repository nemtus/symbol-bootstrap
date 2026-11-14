#!/usr/bin/env python3

"""
Auto-resolve the one upstream-sync conflict that is structural and recurring: the package `version`
lines in `package.json` / `package-lock.json`.

Run from the repository root with a conflicted merge in progress (see `mirror-sync.yml`).

Why this exists
---------------
The NEMTUS fork renames the package (`symbol-bootstrap` -> `@nemtus/symbol-bootstrap`), and in both
files the `name` and `version` lines are adjacent. Every upstream version bump therefore lands inside
the same diff hunk as the NEMTUS rename and git reports a conflict, even though the correct resolution
is always mechanical: keep the NEMTUS name, take the newer version.

How it resolves
---------------
Not by preferring a side -- that would silently drop whatever else upstream changed in the file (a new
dependency, a script). Instead every version VALUE listed below is replaced by a sentinel in all three
merge stages, the three-way merge is retried, and the sentinel is filled back in afterwards with the
higher of the two versions (semver ordering, so `1.1.13` vs `1.1.14` -> `1.1.14`, and a NEMTUS-only
`1.1.14` vs an unchanged upstream `1.1.13` -> `1.1.14`).

The version lines are thus the ONLY thing this script decides. If a file still conflicts once the
version is out of the picture, upstream changed something that needs a human, and the file is left
unmerged -- which keeps `mirror-sync`'s conflict path (fail the run, report in the job summary) intact
for everything that is not this one known case.

Adapted from nemtus/symbol-product (`.github/scripts/auto-resolve-version-conflicts.py`).
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

SENTINEL = '@@NEMTUS_MIRROR_SYNC_VERSION_SENTINEL@@'

# The files the fork layer rewrites, each with the patterns matching their package version VALUE (group
# 'version'). Every pattern must match exactly once, and all of a file's matches must carry the same
# version. Anything not listed here is never touched.
RESOLVABLE_FILES = {
	'package.json': [
		re.compile(r'\A\{\n    "name": "[^"]+",\n(?:    "[^"]+": [^\n]*\n)*?    "version": "(?P<version>[^"]+)",$', re.M),
	],
	'package-lock.json': [
		# root
		re.compile(r'\A\{\n    "name": "[^"]+",\n    "version": "(?P<version>[^"]+)",$', re.M),
		# packages[""] (the project itself; NOT the node_modules/* entries)
		re.compile(r'^        "": \{\n            "name": "[^"]+",\n            "version": "(?P<version>[^"]+)",$', re.M),
	],
}

SEMVER = re.compile(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$')


def _git(*args, check=True):
	return subprocess.run(['git', *args], capture_output=True, text=True, check=check)


def unmerged_paths():
	return [line for line in _git('diff', '--name-only', '--diff-filter=U').stdout.splitlines() if line]


def _stage(stage, path):
	"""Content of a merge stage: 1 = merge base, 2 = ours, 3 = theirs. None when the stage is absent."""

	result = _git('show', f':{stage}:{path}', check=False)
	return result.stdout if 0 == result.returncode else None


def _version_key(version):
	"""Semver precedence key: a release sorts above its prereleases; prerelease ids compare per semver."""

	match = SEMVER.match(version)
	if not match:
		raise ValueError(f'not a semver version: {version}')

	release = tuple(int(part) for part in match.group(1, 2, 3))
	pre = match.group(4)
	if pre is None:
		return (release, 1, ())

	identifiers = tuple((0, int(part), '') if part.isdigit() else (1, 0, part) for part in pre.split('.'))
	return (release, 0, identifiers)


def _pick_version(ours, theirs):
	return ours if _version_key(ours) >= _version_key(theirs) else theirs


def _sentinelize(patterns, text):
	"""Replace every version value with the sentinel. Returns (text, version), or (None, None)."""

	spans = []
	versions = set()
	for pattern in patterns:
		matches = list(pattern.finditer(text))
		if 1 != len(matches):
			return None, None
		spans.append(matches[0].span('version'))
		versions.add(matches[0].group('version'))

	if 1 != len(versions):
		return None, None

	for start, end in sorted(spans, reverse=True):
		text = text[:start] + SENTINEL + text[end:]
	return text, versions.pop()


def _merge_file(ours, base, theirs):
	"""Three-way merge of three strings. Returns the merged text, or None when it conflicts."""

	with tempfile.TemporaryDirectory() as directory:
		paths = []
		for name, content in (('ours', ours), ('base', base), ('theirs', theirs)):
			path = Path(directory) / name
			path.write_text(content, encoding='utf8')
			paths.append(str(path))

		# `git merge-file -p a b c` merges the changes that took b -> c into a and prints the result;
		# a nonzero exit status is the number of conflicts left behind.
		result = _git('merge-file', '-p', '--no-diff3', *paths, check=False)
		return result.stdout if 0 == result.returncode else None


def resolve(path, patterns):
	"""Try to resolve one conflicted file. Returns a description of the resolution, or None."""

	base, ours, theirs = (_stage(stage, path) for stage in (1, 2, 3))
	if base is None or ours is None or theirs is None:
		print(f'{path}: not a three-way content conflict (add/add or delete/modify); leaving unmerged')
		return None

	masked_ours, ours_version = _sentinelize(patterns, ours)
	masked_theirs, theirs_version = _sentinelize(patterns, theirs)
	if not ours_version or not theirs_version:
		print(f'{path}: could not locate the version line(s) on both sides; leaving unmerged')
		return None

	try:
		version = _pick_version(ours_version, theirs_version)
	except ValueError as error:
		print(f'{path}: {error}; leaving unmerged')
		return None

	# The base may predate the layout; masking it is best effort.
	masked_base = _sentinelize(patterns, base)[0] or base

	merged = _merge_file(masked_ours, masked_base, masked_theirs)
	if merged is None:
		print(f'{path}: conflicts beyond the version line(s); leaving unmerged for manual resolution')
		return None

	if len(patterns) != merged.count(SENTINEL):
		print(f'{path}: version line(s) did not survive the merge intact; leaving unmerged')
		return None

	Path(path).write_text(merged.replace(SENTINEL, version), encoding='utf8')
	_git('add', '--', path)

	kept = 'ours' if version == ours_version else 'upstream'
	return f'{path}: version {ours_version} (ours) + {theirs_version} (upstream) -> {version} ({kept})'


def main():
	conflicted = unmerged_paths()
	if not conflicted:
		print('no unmerged files')
		return 0

	print('unmerged files:\n  ' + '\n  '.join(conflicted))

	resolutions = []
	for path in conflicted:
		patterns = RESOLVABLE_FILES.get(path)
		if patterns is None:
			print(f'{path}: not a known fork-layer packaging file; leaving unmerged')
			continue

		resolution = resolve(path, patterns)
		if resolution:
			resolutions.append(resolution)

	if resolutions:
		print('\nauto-resolved:\n  ' + '\n  '.join(resolutions))

	remaining = unmerged_paths()
	if remaining:
		print('\nstill unmerged:\n  ' + '\n  '.join(remaining))
		return 1

	# Consumed by mirror-sync.yml to describe the resolution in the PR body. `--git-path` resolves
	# inside the real git directory, which is not `./.git` in a worktree.
	report = Path(_git('rev-parse', '--git-path', 'NEMTUS_AUTO_RESOLUTIONS').stdout.strip())
	report.write_text('\n'.join(resolutions) + '\n', encoding='utf8')

	print('\nall conflicts auto-resolved')
	return 0


if __name__ == '__main__':
	sys.exit(main())
