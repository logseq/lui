#!/usr/bin/env bash
# Build the existing OCaml Todos application for any native desktop host.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
case "$(uname -s)" in
  Darwin)
    opam exec -- dune build examples/todos/native/liblui_todos.dylib
    printf '%s\n' "$repo_root/_build/default/examples/todos/native/liblui_todos.dylib"
    ;;
  Linux)
    opam exec -- dune build src/lui.cmxa examples/todos/todos_app.cmxa \
      examples/todos/native/todos_bridge.cmxa
    output_dir="$repo_root/_build/mygo"
    mkdir -p "$output_dir"
    opam exec -- ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
      -runtime-variant _pic -ccopt -fPIC \
      _build/default/src/lui.cmxa \
      _build/default/examples/todos/todos_app.cmxa \
      _build/default/examples/todos/native/todos_bridge.cmxa \
      -output-complete-obj -o "$output_dir/todos_complete.o"
    ocaml_include=$(opam exec -- ocamlc -where)
    cc -fPIC -shared -o "$output_dir/liblui_todos.so" \
      platform/native/lui_ocaml_bridge.c "$output_dir/todos_complete.o" \
      -I"$ocaml_include" -lpthread -ldl -lm
    printf '%s\n' "$output_dir/liblui_todos.so"
    ;;
  *) printf 'Build an OCaml lui_ocaml_* library with your platform toolchain.\n' >&2; exit 1 ;;
esac
