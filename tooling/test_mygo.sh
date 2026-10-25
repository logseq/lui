#!/usr/bin/env bash
# Run the real OCaml -> wire -> MyGo -> input -> OCaml integration, with races.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
python3 tooling/generate_mygo_schema.py --check
python3 -m unittest discover -s tooling/test -p 'test_mygo_*.py'
# Allocation budgets use the shipping configuration; behavioral tests also run
# with the race detector, whose instrumentation changes allocation counts.
go -C platform/mygo test -count=1 -run 'AllocationBudget$' .
case "${1:-integration}" in
  --unit)
    go -C platform/mygo test -race -count=1 ./...
    exit
    ;;
  integration) ;;
  *) printf 'Usage: %s [integration|--unit]\n' "$0" >&2; exit 2 ;;
esac

# Export compiler intermediates and oracle vectors outside the repository.
oracle_directory=$(mktemp -d "${TMPDIR:-/tmp}/lui-mygo-oracle.XXXXXX")
trap 'rm -rf "$oracle_directory"' EXIT
oracle_file="$oracle_directory/contract.json"
python3 tooling/generate_mygo_schema.py --export --oracle-output "$oracle_file"
test -s "$oracle_file" || { printf 'Missing required canonical oracle\n' >&2; exit 1; }
LUI_MYGO_CONTRACT_ORACLE="$oracle_file" go -C platform/mygo test -race -count=1 \
  -run '^TestContractMatchesCanonicalOCamlOracle$' ./...

# One OCaml runtime library per process. Build serially: both targets share
# Dune's build directory, while runtime entry stays on each Go worker thread.
todos_library=$("$repo_root/tooling/build_mygo_todos.sh")
components_library=$("$repo_root/tooling/build_mygo_components.sh")
test -s "$todos_library" || { printf 'Missing required Todos library\n' >&2; exit 1; }
test -s "$components_library" || { printf 'Missing required Components library\n' >&2; exit 1; }

LUI_MYGO_TEST_LIBRARY="$todos_library" go -C platform/mygo test -race -count=1 \
  -run '^(TestOCamlTodos|TestRuntimePreservesWorkerSignalStack)' ./...
LUI_MYGO_COMPONENTS_LIBRARY="$components_library" go -C platform/mygo test -race -count=1 \
  -run '^TestOCamlComponents' ./...
LUI_MYGO_TEST_LIBRARY="$todos_library" \
LUI_MYGO_COMPONENTS_LIBRARY="$components_library" \
  go -C platform/mygo test -race -count=1 -run '^TestRuntimeFreshProcessStartup$' ./...
