# NEMTUS maintenance fork of symbol/symbol-bootstrap

This repository is the NEMTUS-maintained fork of
[`symbol/symbol-bootstrap`](https://github.com/symbol/symbol-bootstrap) (tracked branch: `dev`),
published to npm as [`@nemtus/symbol-bootstrap`](https://www.npmjs.com/package/@nemtus/symbol-bootstrap).

## Why it exists, and how it differs from the other NEMTUS mirrors

symbol-bootstrap is the legacy node-setup tool; new deployments should use shoestring
(`nemtus-symbol-shoestring`, see `nemtus/symbol-product`). Some operators still depend on bootstrap,
and upstream stopped publishing to npm at `symbol-bootstrap@1.1.10` (2023-05) although it kept tagging
GitHub releases (v1.1.11 – v1.1.13). This fork keeps the tool installable and minimally maintained —
following upstream, Node.js runtime support, Docker tooling compatibility and security patches — for as
long as it is needed.

Unlike `nemtus/symbol-product` / `nemtus/symbol-networks`, this fork **does not** replace upstream
assets: the Docker images stay `symbolplatform/*` as upstream ships them in `presets/shared.yml`, and the
network presets are upstream's. The NEMTUS delta is limited to packaging, CI/release and small patches.

## The fork layer (what differs from upstream)

| Area | upstream | NEMTUS fork |
|---|---|---|
| npm package | `symbol-bootstrap` (last published 1.1.10) | **`@nemtus/symbol-bootstrap`** (CLI command still `symbol-bootstrap`) |
| Node.js | `engines: >=14`, CI on 14/16/18 | **`engines: >=24`**, CI on Node.js 24 |
| Docker Compose | spawns `docker-compose` (Compose V1, EOL) | **`docker compose` (V2)**, falling back to `docker-compose`; override with `SYMBOL_BOOTSTRAP_DOCKER_COMPOSE` |
| CI / release | `build.yml`, `alpha.yml`, `release.yml` (unpinned actions, `NPM_TOKEN`) | removed; **`ci.yml`**, **`publish.yml`** (SHA-pinned, OIDC Trusted Publishing + provenance), **`mirror-sync.yml`** |
| npm hardening | — | `.npmrc` (`ignore-scripts`, `min-release-age`), Socket Firewall on every CI install |
| Security patches | — | direct-dependency bumps and `overrides` in `package.json` (see below) |
| Docker images, presets | `symbolplatform/*` | **unchanged** by default; tags kept current by `image-watch.yml`, backed up to ghcr.io by `image-backup.yml` |
| Runtime fixes | — | `nofile` ulimits (65536) on the mongo/server/broker services for Docker 29+; `metal` section in the generated `rest.json` (`restMetalCacheTtl` / `restMetalSizeLimit`) |

NEMTUS source patches are marked with a `NEMTUS:` comment so they are easy to find in a conflict.

## Security patches

The supported surface is the **production** dependency tree (what `npm install -g` installs).
`ci.yml` runs `npm audit --omit=dev --audit-level=high` on every PR and push, and `publish.yml` refuses
to publish with a critical one. When an advisory appears:

1. Prefer a lockfile-only update when the fixed version is inside the declared range.
2. For a transitive dependency outside the range, add an entry to `overrides` in `package.json` (this
   keeps the upstream source untouched). Example: `symbol-sdk` 2.x pins `merkletreejs@^0.2`, whose
   `crypto-js` 3.x / `web3-utils` chain is vulnerable; it is overridden to `^0.4.1`.
3. For a direct dependency, bump it in `dependencies` (npm rejects an override that contradicts a
   direct dependency's spec).
4. Run the unit tests and the e2e, and add a `NEMTUS-CHANGELOG.md` entry.

`symbol-sdk` 2.x itself is end-of-life; migrating to 3.x is a rewrite and out of scope unless an
unpatchable advisory forces it.

## Docker images: watch and backup

The fork keeps upstream's images (`presets/shared.yml`) but does not depend on upstream to keep them
current or available.

- **`image-watch.yml`** (Mondays 05:17 UTC + manual) runs `.github/scripts/image-updates.mjs`, which
  looks for newer Docker Hub tags that are at least 7 days old:

  | Preset key | Image | Proposed when |
  |---|---|---|
  | `symbolServerImage` | `symbolplatform/symbol-server` | newer `gcc-X.Y.Z.W` |
  | `symbolRestImage` | `symbolplatform/symbol-rest` | newer `X.Y.Z`, same major |
  | `mongoImage` | `mongo` | newer patch of the pinned major.minor (minor/major = data migration, never automatic) |
  | `httpsPortalImage` | `steveltn/https-portal` | newer `X.Y.Z`, same major |

  If any, it opens (or updates) one PR from the automation-owned branch `nemtus/image-updates` that
  bumps the preset **and** every test fixture that references the old tag (`test/composes/*.yml`), so
  the unit suite and the e2e run against the new images. Upstream usually bumps `symbol-server` /
  `symbol-rest` in its own releases (arriving via mirror-sync): merge such a PR early only when needed
  (e.g. security), otherwise close it. Explorer/faucet images are upstream alpha builds and not watched.

  Run it locally: `node .github/scripts/image-updates.mjs` (report only) or `--apply`
  (`MIN_AGE_DAYS=0` to ignore the cooldown).

- **`image-backup.yml`** (on preset changes on `dev`, Mondays 05:47 UTC, manual) copies every image
  pinned in `presets/shared.yml` to **`ghcr.io/nemtus/symbol-bootstrap-images/<image>:<tag>`**
  (registry-to-registry, linux/amd64 + linux/arm64; existing backup tags are never overwritten). To run
  on the backups — e.g. if an image disappears from Docker Hub — override the images in a custom
  preset:

  ```yaml
  # custom.yml  (symbol-bootstrap start -p mainnet -a dual -c custom.yml)
  symbolServerImage: ghcr.io/nemtus/symbol-bootstrap-images/symbol-server:gcc-1.0.3.10
  symbolRestImage: ghcr.io/nemtus/symbol-bootstrap-images/symbol-rest:2.5.2
  mongoImage: ghcr.io/nemtus/symbol-bootstrap-images/mongo:7.0.45
  httpsPortalImage: ghcr.io/nemtus/symbol-bootstrap-images/https-portal:1.25.6
  ```

  The backup packages must be **public** (Package settings → Change visibility) for anonymous pulls.

Both workflows page Discord (`DISCORD_WEBHOOK_URL`) on failure, and `mirror-sync.yml`'s keepalive
keeps their schedules from being auto-disabled.

## Fork invariants

An upstream merge can silently revert the fork layer, so it is asserted on every PR by the `parity`
job of `ci.yml`:

```bash
bash .github/scripts/check-nemtus-mirror-invariants.sh
```

It checks the package identity (name, repository, publishConfig, `bin`/`oclif.bin` unchanged,
`engines`), that `package-lock.json` agrees with `package.json`, that upstream's publish workflows stay
removed and no workflow uses `NPM_TOKEN`, that every action is SHA-pinned, that the Docker Compose V2
patch is in place, and that the README carries the fork notice.

## Following upstream

`mirror-sync.yml` (daily 04:37 UTC + manual `workflow_dispatch`) tracks `symbol/symbol-bootstrap:dev`
exactly like the other NEMTUS mirrors:

1. fetches upstream; fast-path no-op if `dev` already contains every upstream commit;
2. otherwise merges upstream into a `sync/upstream-<sha>` branch:
   - **clean merge** → opens a PR;
   - **conflict in the `version` lines of `package.json` / `package-lock.json` only** (what every
     upstream version bump produces, since they sit next to the renamed `name`) → auto-resolved by
     `.github/scripts/auto-resolve-version-conflicts.py` (higher semver wins; nothing else in the file
     is decided by the script), then a PR that quotes the resolution;
   - **any other conflict** → the run fails with the conflicting files, hunks and resolution steps in
     the job summary;
3. keeps a single open sync PR (`.github/scripts/close-superseded-sync-prs.sh`, shared verbatim with
   the other mirrors).

> **Always merge a sync PR with a MERGE COMMIT (not squash).** Squashing drops the upstream parent and
> breaks every later sync.

To resolve a conflict locally:

```bash
git checkout dev && git pull
bash .github/scripts/resolve-upstream-sync.sh
git config rerere.enabled true   # once: replays recurring resolutions
```

Sync PRs are opened by `github-actions[bot]`, so their CI runs wait for **"Approve workflows to run"**.

## Versioning

- A NEMTUS release normally carries the **upstream version it is based on** (e.g. `1.1.13`).
- A **NEMTUS-only** fix (security patch, compatibility fix) bumps the **patch** version (e.g. `1.1.14`)
  and names its upstream base in [`NEMTUS-CHANGELOG.md`](../NEMTUS-CHANGELOG.md).
- When upstream later releases, the sync auto-resolver keeps the higher version; if that number was
  already published by NEMTUS, bump the patch once more before releasing.
- Prerelease suffixes such as `1.1.13-nemtus.1` are **not** used: semver orders them *before* `1.1.13`,
  so `^`/`~` ranges would not pick them up.

## Releasing

1. Open a PR that sets `version` in `package.json` **and** `package-lock.json` (`npm version <x.y.z>
   --no-git-tag-version`) and moves the `Unreleased` entry in `NEMTUS-CHANGELOG.md` under the version.
2. After it is merged (CI green), tag the merge commit and push the tag:

   ```bash
   git checkout dev && git pull
   git tag nemtus-v<x.y.z>
   git push origin nemtus-v<x.y.z>
   ```

   The `nemtus-` prefix keeps NEMTUS tags apart from upstream's `v<x.y.z>` tags.
3. `publish.yml` runs: full CI on the tag → pack → **approval** (`npm-production` environment) →
   `npm publish` (OIDC, provenance) → **verify**: `npm install -g @nemtus/symbol-bootstrap@<x.y.z>` from
   the registry and run a local network with the `symbol-bootstrap` command → GitHub Release.

The pack job refuses to publish while `npm audit --omit=dev` reports a **critical** vulnerability.

## CI

`ci.yml` runs on every PR to `dev` and every push to `dev` (not path-filtered, so the checks can be
required): `parity`, `lint`, `test` (build + upstream unit suite, which uses Docker and the upstream
`symbol-server` image) and `e2e` (packs the package exactly as published, installs it with
`npm install -g`, starts a local network with `symbol-bootstrap start -p bootstrap` and waits for the
chain to grow). The same checks run locally:

```bash
npm ci && npm run lint && npm run build && npm test
bash .github/scripts/pack.sh /tmp/pack
NPM_CONFIG_PREFIX=/tmp/prefix bash .github/scripts/e2e.sh /tmp/pack/nemtus-symbol-bootstrap-*.tgz /tmp/e2e
```

`npm test` updates `lastKnownNetworkEpoch` in `presets/*/network.yml` and rewrites
`test/**/encrypted.yml` as a side effect (upstream behaviour) — do not commit those changes.

## Runtime dependencies on upstream infrastructure

The tool itself still reaches upstream-operated services at runtime; if they disappear, the
corresponding feature degrades and a NEMTUS patch (or a custom preset) is needed:

| Used for | Endpoint (preset) |
|---|---|
| Docker images | Docker Hub `symbolplatform/symbol-server`, `symbolplatform/symbol-rest`, `mongo`, `steveltn/https-portal` (`presets/shared.yml`); backups in `ghcr.io/nemtus/symbol-bootstrap-images` |
| Peer / REST discovery | `nodewatch.symbol.tools` (`presets/{mainnet,testnet}/network.yml`, `nodeWatchUrl`) |
| Testnet peers | `*.symboltest.net` (`presets/testnet/network.yml`) |
| Links shown to users | `symbol.fyi`, `testnet.symbol.fyi`, `testnet.symbol.tools` |

Operators can override any image or URL with a custom preset (`-c custom.yml`); see the image backups
above.
