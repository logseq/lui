#!/usr/bin/env bash
# Builds the OCaml LUI runtime (todos app + native bridge) as a merged
# relocatable object the Qt/QML demo links into its executable. Mirrors the
# macOS dune rule in examples/todos/native/dune — but on Linux the OCaml
# -output-complete-obj artifact is not PIC, so it cannot live in a shared
# library; it must be linked into the main binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$OUT_DIR/lui_todos_runtime.o"

eval "$(opam env)"

cd "$REPO_ROOT"
dune build src/lui.cmxa \
    examples/todos/todos_app.cmxa \
    examples/todos/native/todos_bridge.cmxa

BUILD="$REPO_ROOT/_build/default"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
    "$BUILD/src/lui.cmxa" \
    "$BUILD/examples/todos/todos_app.cmxa" \
    "$BUILD/examples/todos/native/todos_bridge.cmxa" \
    -output-complete-obj -o "$WORK/todos_bridge_complete.o"

cc -c -fPIC -o "$WORK/lui_ocaml_bridge.o" \
    "$REPO_ROOT/platform/native/lui_ocaml_bridge.c" \
    -I"$(ocamlfind ocamlc -where)"

ld -r -o "$OUT" "$WORK/todos_bridge_complete.o" "$WORK/lui_ocaml_bridge.o"

echo "Built $OUT"
