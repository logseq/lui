#!/usr/bin/env bash
# Builds an OCaml LUI runtime (app + native bridge) as a merged relocatable
# object the Qt/QML demo links into its executable. Usage:
#   build-runtime.sh [todos|gallery]
# Mirrors the macOS dune rules in examples/*/native/dune — but on Linux the
# OCaml -output-complete-obj artifact is not PIC, so it cannot live in a
# shared library; it must be linked into the main binary.
set -euo pipefail

APP="${1:-todos}"
case "$APP" in
    todos)
        APP_CMXA="examples/todos/todos_app.cmxa"
        BRIDGE_CMXA="examples/todos/native/todos_bridge.cmxa"
        ;;
    gallery)
        APP_CMXA="examples/gallery/gallery_app.cmxa"
        BRIDGE_CMXA="examples/components/native/components_bridge.cmxa"
        ;;
    *)
        echo "unknown app '$APP' (expected todos or gallery)" >&2
        exit 2
        ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$OUT_DIR/lui_${APP}_runtime.o"

eval "$(opam env)"

cd "$REPO_ROOT"
dune build src/lui.cmxa "$APP_CMXA" "$BRIDGE_CMXA"

BUILD="$REPO_ROOT/_build/default"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
    "$BUILD/src/lui.cmxa" \
    "$BUILD/$APP_CMXA" \
    "$BUILD/$BRIDGE_CMXA" \
    -output-complete-obj -o "$WORK/bridge_complete.o"

cc -c -fPIC -o "$WORK/lui_ocaml_bridge.o" \
    "$REPO_ROOT/platform/native/lui_ocaml_bridge.c" \
    -I"$(ocamlfind ocamlc -where)"

ld -r -o "$OUT" "$WORK/bridge_complete.o" "$WORK/lui_ocaml_bridge.o"

echo "Built $OUT"
