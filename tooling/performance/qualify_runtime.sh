#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
results=$(mktemp "${TMPDIR:-/tmp}/lui-performance.XXXXXX")
bench_dir=$(mktemp -d "${TMPDIR:-/tmp}/lui-bench.XXXXXX")
trap 'rm -f "$results"; rm -rf "$bench_dir"' EXIT

local_text_limit=${LUI_PERF_LOCAL_TEXT_1K_MS_MAX:-10}
typing_limit=${LUI_PERF_TYPING_10K_60_MS_MAX:-250}
keyed_reorder_limit=${LUI_PERF_KEYED_REORDER_1K_MS_MAX:-25}
keyed_edit_limit=${LUI_PERF_KEYED_MIDDLE_EDIT_1K_MS_MAX:-25}
scroll_limit=${LUI_PERF_SCROLL_BACKGROUND_MS_MAX:-10}
sustained_limit=${LUI_PERF_SUSTAINED_MUTATIONS_10K_MS_MAX:-1000}

check_budget() {
  local metric=$1
  local limit=$2
  local value
  value=$(awk -v metric="$metric" '$1 == "LUI_PERF" && $2 == metric { print $3 }' "$results")
  [[ -n $value ]] || {
    echo "error: benchmark did not report $metric" >&2
    exit 1
  }
  awk -v metric="$metric" -v value="$value" -v limit="$limit" 'BEGIN {
    if (value > limit) {
      printf "error: %s took %.3f ms (budget %.3f ms)\n", metric, value, limit > "/dev/stderr"
      exit 1
    }
    printf "pass: %s %.3f ms <= %.3f ms\n", metric, value, limit
  }'
}

cd "$repo_root"
opam exec -- dune build src/lui.cmxa -j 1
cp tooling/performance/runtime_bench.ml "$bench_dir/"
opam exec -- ocamlfind ocamlopt -linkpkg -package ocaml-signal,unix \
  -I "$repo_root/_build/default/src/.lui.objs/byte" \
  -I "$repo_root/_build/default/src/.lui.objs/native" \
  "$repo_root/_build/default/src/lui.cmxa" \
  "$bench_dir/runtime_bench.ml" -o "$bench_dir/runtime_bench"
if ! "$bench_dir/runtime_bench" >"$results"; then
  sed -n '1,240p' "$results"
  exit 1
fi
awk '$1 == "LUI_PERF" { print }' "$results"

check_budget local_text_1k_ms "$local_text_limit"
check_budget typing_10k_nodes_60_updates_ms "$typing_limit"
check_budget keyed_reorder_1k_ms "$keyed_reorder_limit"
check_budget keyed_middle_edit_1k_ms "$keyed_edit_limit"
check_budget scroll_background_ms "$scroll_limit"
check_budget sustained_local_mutations_10k_ms "$sustained_limit"

check_budget flat_mount_10k_ms "${LUI_PERF_FLAT_MOUNT_10K_MS_MAX:-500}"
check_budget wide_reorder_10k_ms "${LUI_PERF_WIDE_REORDER_10K_MS_MAX:-250}"
check_budget branch_mount_dispose_1k_ms "${LUI_PERF_BRANCH_LIFECYCLE_1K_MS_MAX:-250}"
