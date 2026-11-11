#!/usr/bin/env bash
# Build the existing OCaml Todos application for any native desktop host.
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
    opam exec -- dune build examples/todos/native/liblui_todos.dylib
    write_receipt "$repo_root/_build/default/examples/todos/native/liblui_todos.dylib" "bash tooling/build_nsh_todos.sh" \
      --input src --input ppx --input examples/todos --input platform/bridge
    printf '%s\n' "$repo_root/_build/default/examples/todos/native/liblui_todos.dylib"
    ;;
  Linux)
    opam exec -- dune build src/lui.cmxa examples/todos/todos_app.cmxa \
      examples/todos/native/todos_bridge.cmxa
    output_dir="$repo_root/_build/nsh"
    mkdir -p "$output_dir"
    opam exec -- ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
      -runtime-variant _pic -ccopt -fPIC \
      _build/default/src/lui.cmxa \
      _build/default/examples/todos/todos_app.cmxa \
      _build/default/examples/todos/native/todos_bridge.cmxa \
      -output-complete-obj -o "$output_dir/todos_complete.o"
    ocaml_include=$(opam exec -- ocamlc -where)
    cc -fPIC -shared -o "$output_dir/liblui_todos.so" \
      platform/bridge/lui_ocaml_bridge.c "$output_dir/todos_complete.o" \
      -I"$ocaml_include" -lpthread -ldl -lm
    write_receipt "$output_dir/liblui_todos.so" "bash tooling/build_nsh_todos.sh" \
      --input src --input ppx --input examples/todos --input platform/bridge
    printf '%s\n' "$output_dir/liblui_todos.so"
    ;;
  *) printf 'Build an OCaml lui_ocaml_* library with your platform toolchain.\n' >&2; exit 1 ;;
esac
