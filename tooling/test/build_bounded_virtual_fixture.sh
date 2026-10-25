#!/usr/bin/env bash
# Build a portable real-OCaml application for native host integration tests.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
output_dir=${1:?usage: build_bounded_virtual_fixture.sh OUTPUT_DIRECTORY}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
cd "$repo_root"
native_flags=(-ccopt -fPIC)
case "$(uname -s)" in
  Darwin) ;;
  Linux) native_flags+=(-runtime-variant _pic) ;;
  *) printf 'The native fixture requires a macOS or Linux toolchain.\n' >&2; exit 1 ;;
esac
opam exec -- dune build ppx/lui_ppx.cmxa src/lui.cmxa
printf '%s\n' 'let () = Ppxlib.Driver.standalone ()' > "$output_dir/driver.ml"
opam exec -- ocamlfind ocamlopt -package ppxlib -linkpkg -linkall \
  _build/default/ppx/lui_ppx.cmxa "$output_dir/driver.ml" -o "$output_dir/driver"
cp tooling/test/fixtures/bounded_virtual_bridge.ml "$output_dir/"
opam exec -- ocamlfind ocamlopt -linkpkg -linkall -package ocaml-signal \
  "${native_flags[@]}" \
  -ppx "$output_dir/driver --as-ppx" \
  -I _build/default/src/.lui.objs/byte -I _build/default/src/.lui.objs/native \
  _build/default/src/lui.cmxa "$output_dir/bounded_virtual_bridge.ml" \
  -output-complete-obj -o "$output_dir/bounded_virtual_complete.o"
opam exec -- ocamlopt -ccopt -fPIC -c platform/native/lui_ocaml_bridge.c \
  -o "$output_dir/lui_ocaml_bridge.o"
case "$(uname -s)" in
  Darwin)
    cc -dynamiclib "$output_dir/bounded_virtual_complete.o" \
      "$output_dir/lui_ocaml_bridge.o" -o "$output_dir/liblui_bounded_virtual.dylib"
    ;;
  Linux)
    cc -shared "$output_dir/bounded_virtual_complete.o" \
      "$output_dir/lui_ocaml_bridge.o" -lm -ldl -pthread \
      -o "$output_dir/liblui_bounded_virtual.so"
    ;;
esac
