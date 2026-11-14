#!/bin/bash
#
# pack.sh <destination-dir>
#
# Builds and packs @nemtus/symbol-bootstrap exactly as it is published (used by CI e2e and the publish
# workflow). The repo's .npmrc sets ignore-scripts=true, so upstream's prepack/postpack hooks do not
# run; this script performs the relevant steps explicitly: compile, generate the oclif manifest (faster
# CLI start-up), pack, then remove the manifest again (it is a build artifact, git-ignored).

set -euo pipefail

DEST="${1:?usage: pack.sh <destination-dir>}"
cd "$(git rev-parse --show-toplevel)"
mkdir -p "$DEST"

npm run build
npx --no-install oclif-dev manifest
trap 'rm -f oclif.manifest.json' EXIT
npm pack --pack-destination "$DEST"
ls -l "$DEST"
