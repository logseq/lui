#!/usr/bin/env bash
# Build the existing Components application for the desktop MyGo bridge.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
# Records what the artifact was built from, so tooling/lui_agent.mjs refuses
# to drive it once its sources change. Builds without Node skip the receipt.
write_receipt() {
  local tool="$repo_root/tooling/lui_build_receipt.mjs"
  if command -v node >/dev/null 2>&1 && [[ -f $tool ]]; then
    node "$tool" write --root "$repo_root" --artifact "$1" --command "$2" "${@:3}" >&2 \
      || echo "warning: could not write a build receipt for $1" >&2
  fi
}
case "$(uname -s)" in
  Darwin)
    opam exec -- dune build examples/components/native/liblui_components.dylib
    write_receipt "$repo_root/_build/default/examples/components/native/liblui_components.dylib" "bash tooling/build_mygo_components.sh" \
      --input src --input ppx --input examples/gallery --input examples/components/native --input platform/bridge
    printf '%s\n' "$repo_root/_build/default/examples/components/native/liblui_components.dylib"
    ;;
  Linux)
    opam exec -- dune build src/lui.cmxa examples/gallery/gallery_app.cmxa \
      examples/components/native/components_bridge.cmxa
    output_dir="$repo_root/_build/mygo"
    mkdir -p "$output_dir"
    opam exec -- ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
      -runtime-variant _pic -ccopt -fPIC \
      _build/default/src/lui.cmxa \
      _build/default/examples/gallery/gallery_app.cmxa \
      _build/default/examples/components/native/components_bridge.cmxa \
      -output-complete-obj -o "$output_dir/components_complete.o"
    ocaml_include=$(opam exec -- ocamlc -where)
    cc -fPIC -shared -o "$output_dir/liblui_components.so" \
      platform/bridge/lui_ocaml_bridge.c "$output_dir/components_complete.o" \
      -I"$ocaml_include" -lpthread -ldl -lm
    write_receipt "$output_dir/liblui_components.so" "bash tooling/build_mygo_components.sh" \
      --input src --input ppx --input examples/gallery --input examples/components/native --input platform/bridge
    printf '%s\n' "$output_dir/liblui_components.so"
    ;;
  *) printf 'Build an OCaml lui_ocaml_* library with your platform toolchain.\n' >&2; exit 1 ;;
esac
