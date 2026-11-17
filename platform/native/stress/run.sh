#!/bin/sh
# Compile and run the C1 GC stress test against the real native bridge.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cp "$root/platform/native/lui_ocaml_bridge.c" \
  "$root/platform/native/lui_caml_dispatch.h" \
  "$root/platform/native/stress/stress_driver.c" \
  "$root/platform/native/stress/stress.ml" \
  "$out/"
(
  cd "$out"
  ocamlopt -o stress -I . lui_ocaml_bridge.c stress_driver.c stress.ml
  OCAMLRUNPARAM=s=4k ./stress
)
