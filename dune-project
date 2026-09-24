(lang dune 3.17)
(using melange 0.1)

(name lui)
(version 0.1.0)

(generate_opam_files true)

(package
 (name lui)
 (maintainers "Tienson Qin <tiensonqin@gmail.com>")
 (authors "Tienson Qin")
 (license "MIT")
 (synopsis "A reactive retained cross-platform UI runtime in OCaml")
 (description
  "Declarative UI, incremental patch batching, and Apple, Flutter, and Web backends powered by ocaml-signal. Element constructors follow the convention unit -> ?props -> children:t list -> unit -> t so optional props erase under a trailing unit argument.")
 (depends
  (ocaml (>= 5.1))
  (dune (>= 3.17))
  (melange (>= 6.0))
  melange-webapi
  ocaml-signal
  yojson
  (alcotest :with-test)))
