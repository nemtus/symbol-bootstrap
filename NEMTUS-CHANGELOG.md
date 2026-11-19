# NEMTUS changelog

Releases of [`@nemtus/symbol-bootstrap`](https://www.npmjs.com/package/@nemtus/symbol-bootstrap). Each
entry names the upstream [`symbol/symbol-bootstrap`](https://github.com/symbol/symbol-bootstrap) release
it is based on; upstream's own changes are in [`CHANGELOG.md`](CHANGELOG.md).

Versioning: a NEMTUS release normally carries the upstream version it is based on. A NEMTUS-only fix
bumps the patch version (and names its upstream base here); when upstream later releases, the next
NEMTUS release takes the higher of the two plus one patch if needed. See
[`docs/nemtus-fork.md`](docs/nemtus-fork.md#versioning); its
[version map](docs/nemtus-fork.md#version-map) lists the upstream release and Docker images behind
every NEMTUS version.

## Unreleased

## 1.1.14 (2026-11-15)

Based on upstream **v1.1.13**. NEMTUS-only compatibility fixes.

- Docker 29 compatibility: the generated `compose.yml` sets `ulimits.nofile` (soft and hard 65536) on the
  MongoDB, server and broker services. Docker 29 lowered the containers' default soft open-file limit to
  1024, which is too low for catapult (RocksDB) and MongoDB. Same values as upstream shoestring; override
  per service with the `compose` / `brokerCompose` preset property.
- REST: the generated `rest.json` now has the `metal` section required by the Metal decode endpoint
  (`GET /metadata/metal/:metalId`) of symbol-rest 2.4.4+, which failed without it. New preset properties
  `restMetalCacheTtl` (default 300) and `restMetalSizeLimit` (default 10000000), matching symbol-rest's
  defaults.
- Existing nodes pick up both fixes after regenerating their configuration with `--upgrade` (e.g.
  `symbol-bootstrap start --upgrade` with the usual flags).

Both issues were identified and first fixed in the community fork
[nemnesia/symbol-bootstrap](https://github.com/nemnesia/symbol-bootstrap) (thanks to ccHarvestasya).

## 1.1.13 (2026-11-15)

Based on upstream **v1.1.13**. First NEMTUS release.

- Published as `@nemtus/symbol-bootstrap` (the CLI command is still `symbol-bootstrap`).
- Supported runtime: Node.js 24 (`engines.node: >=24`).
- Docker Compose V2 support: the `docker compose` plugin is used when available, falling back to the
  legacy `docker-compose` binary; override with `SYMBOL_BOOTSTRAP_DOCKER_COMPOSE`.
- Security: production dependency tree is free of known vulnerabilities (`npm audit --omit=dev`):
  `figlet` 1.5.2 → 1.11.4, `js-yaml` → ^4.3.2, and `merkletreejs` (a `symbol-sdk` 2.x dependency)
  overridden to ^0.4.1, which drops the vulnerable `crypto-js` 3.x / `web3-utils` / `bn.js` chain.
- Docker images are unchanged from upstream (`symbolplatform/symbol-server:gcc-1.0.3.10`,
  `symbolplatform/symbol-rest:2.5.2`, ...).
