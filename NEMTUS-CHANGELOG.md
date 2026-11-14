# NEMTUS changelog

Releases of [`@nemtus/symbol-bootstrap`](https://www.npmjs.com/package/@nemtus/symbol-bootstrap). Each
entry names the upstream [`symbol/symbol-bootstrap`](https://github.com/symbol/symbol-bootstrap) release
it is based on; upstream's own changes are in [`CHANGELOG.md`](CHANGELOG.md).

Versioning: a NEMTUS release normally carries the upstream version it is based on. A NEMTUS-only fix
bumps the patch version (and names its upstream base here); when upstream later releases, the next
NEMTUS release takes the higher of the two plus one patch if needed. See
[`docs/nemtus-fork.md`](docs/nemtus-fork.md#versioning).

## Unreleased

Based on upstream **v1.1.13**.

- Published as `@nemtus/symbol-bootstrap` (the CLI command is still `symbol-bootstrap`).
- Supported runtime: Node.js 24 (`engines.node: >=24`).
- Docker Compose V2 support: the `docker compose` plugin is used when available, falling back to the
  legacy `docker-compose` binary; override with `SYMBOL_BOOTSTRAP_DOCKER_COMPOSE`.
- Docker images are unchanged from upstream (`symbolplatform/symbol-server:gcc-1.0.3.10`,
  `symbolplatform/symbol-rest:2.5.2`, ...).
