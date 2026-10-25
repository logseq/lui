#!/usr/bin/env bash
# Build the existing Components application for the desktop MyGo bridge.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
case "$(uname -s)" in
  Darwin)
    opam exec -- dune build examples/components/native/liblui_components.dylib
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
      platform/native/lui_ocaml_bridge.c "$output_dir/components_complete.o" \
      -I"$ocaml_include" -lpthread -ldl -lm
    printf '%s\n' "$output_dir/liblui_components.so"
    ;;
  *) printf 'Build an OCaml lui_ocaml_* library with your platform toolchain.\n' >&2; exit 1 ;;
esac
