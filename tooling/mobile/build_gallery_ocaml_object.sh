#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 TARGET_PREFIX BUILD_DIRECTORY [pic]" >&2
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
target_prefix=$(cd "$1" && pwd)
mkdir -p "$2"
build_dir=$(cd "$2" && pwd)
runtime_variant=${3:-default}
ocamlopt="$target_prefix/bin/ocamlopt.opt"
generated_bridge="$repo_root/_build/default/examples/components/native/gallery_bridge.ml"
dependency_root="$build_dir/lg-dependencies"

[[ -f $generated_bridge ]] || {
  echo "error: generate gallery_bridge.ml with Dune before cross compilation" >&2
  exit 1
}

"$repo_root/tooling/mobile/build_lg_dependencies.sh" \
  "$target_prefix" "$dependency_root" >/dev/null

include_args=()
while IFS= read -r directory; do
  include_args+=(-I "$directory")
done <"$dependency_root/include-directories.txt"

"$ocamlopt" "${include_args[@]}" -c "$generated_bridge" \
  -o "$build_dir/gallery_bridge.cmx"

link_args=(-output-complete-obj -linkall)
if [[ $runtime_variant == pic ]]; then
  link_args+=(-runtime-variant _pic)
fi

dependency_objects=()
while IFS= read -r object; do
  dependency_objects+=("$object")
done <"$dependency_root/link-objects.txt"

"$ocamlopt" \
  "${include_args[@]}" \
  "${link_args[@]}" \
  -o "$build_dir/gallery_bridge_complete.o" \
  "${dependency_objects[@]}" \
  "$build_dir/gallery_bridge.cmx"

echo "$build_dir/gallery_bridge_complete.o"
