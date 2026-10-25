#!/usr/bin/env bash
# Run the real OCaml -> wire -> MyGo -> input -> OCaml integration, with races.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
library=$("$repo_root/tooling/build_mygo_todos.sh")
cd "$repo_root"
python3 tooling/generate_mygo_schema.py --check
cd platform/mygo
LUI_MYGO_TEST_LIBRARY="$library" go test -race -count=1 ./...
