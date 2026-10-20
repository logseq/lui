#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
opam exec -- dune build --root "$root" src/lui.cmxa
build="$root/_build/data-view"
mkdir -p "$build"
opam exec -- ocamlfind ocamlopt -package melange-edn-core,ocaml-signal \
  -I "$root/_build/default/src/.lui.objs/byte" -I "$build" \
  -c "$root/examples/data/data_view.mli" -o "$build/data_view.cmi"
opam exec -- ocamlfind ocamlopt -package melange-edn-core,ocaml-signal \
  -I "$root/_build/default/src/.lui.objs/byte" -I "$build" \
  -c "$root/examples/data/data_view.ml" -o "$build/data_view.cmx"
target=main
if [ "${1:-}" = "--check" ]; then target=check; shift; fi
opam exec -- ocamlfind ocamlopt -package melange-edn-core,ocaml-signal \
  -I "$root/_build/default/src/.lui.objs/byte" \
  -I "$root/_build/default/src/.lui.objs/native" -I "$build" \
  -c "$root/examples/data/$target.ml" -o "$build/$target.cmx"
opam exec -- ocamlfind ocamlopt -linkpkg -package melange-edn-core,ocaml-signal \
  -I "$root/_build/default/src" -I "$build" \
  "$root/_build/default/src/lui.cmxa" "$build/data_view.cmx" \
  "$build/$target.cmx" -o "$build/$target.exe"
if [ "$target" = main ] && [ "$#" -eq 0 ]; then
  set -- "$root/examples/data/todos.edn"
fi
exec "$build/$target.exe" "$@"
