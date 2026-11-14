# Repository guide

This repository is the **NEMTUS maintenance fork of
[`symbol/symbol-bootstrap`](https://github.com/symbol/symbol-bootstrap)** (tracked branch: `dev`),
published to npm as **`@nemtus/symbol-bootstrap`**. Most code is unmodified upstream; a small NEMTUS
fork layer (package rename, Node.js 24, Docker Compose V2, CI/release, security patches) keeps it
installable and maintained. Upstream Docker images and presets are used as-is. See
[`docs/nemtus-fork.md`](docs/nemtus-fork.md) for the full picture.

## Conventions

- **Write published artifacts in English** — PR titles/descriptions, commit messages, code comments,
  docs, release notes, workflow comments. (Conversational replies may be in the user's language.)
- **Pin every GitHub Actions `uses:` to a full-length commit SHA** (with a `# vX.Y.Z` comment).
- **Following upstream uses git merge, never squash.** Sync PRs (from `mirror-sync.yml`) must be merged
  with a merge commit to preserve the upstream parent.
- **Keep the delta vs upstream minimal.** Prefer `overrides` in `package.json` for transitive security
  fixes over source edits; mark any source patch with a `NEMTUS:` comment; record user-visible changes
  in `NEMTUS-CHANGELOG.md` (never in upstream's `CHANGELOG.md`).
- **No contributions back to upstream** are planned; do not open PRs against `symbol/symbol-bootstrap`.
- Release tags are `nemtus-vX.Y.Z` (never `vX.Y.Z`, which is upstream's namespace).
- Docker image tags in `presets/shared.yml` are bumped only via the `image-watch.yml` PR flow
  (`.github/scripts/image-updates.mjs --apply` also rewrites the `test/composes/` fixtures).

## Fork layer — do not regress

Validate at any time (also the `parity` CI job):

```bash
bash .github/scripts/check-nemtus-mirror-invariants.sh
```

## Build and test (Node.js 24)

```bash
npm ci                 # .npmrc sets ignore-scripts=true
npm run lint
npm run build
npm test               # needs Docker; rewrites presets/*/network.yml + test/**/encrypted.yml — revert those
bash .github/scripts/pack.sh /tmp/pack
NPM_CONFIG_PREFIX=/tmp/prefix bash .github/scripts/e2e.sh /tmp/pack/nemtus-symbol-bootstrap-*.tgz /tmp/e2e
```
