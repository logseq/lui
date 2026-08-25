#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

opam exec -- dune build -j 1 lg/lui/lui_native.state

lg mobile build "$@" \
  --from "$repo_root/_build/default/lg/lui/lui_native.state" \
  "$repo_root/lg/lui/backend/retained" \
  "$repo_root/lg/lui/backend/flutter" \
  "$repo_root/examples/components/lg/components" \
  "$repo_root/examples/components/native"
