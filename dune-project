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
 (synopsis "A reactive retained cross-platform UI runtime written in LG")
 (description
  "Declarative UI, incremental patch batching, and Apple, Flutter, and Web backends powered by signal-lg.")
 (depends
  (ocaml (>= 5.4))
  (dune (>= 3.17))
  (melange (>= 6.0))
  melange-webapi
  lg
  lg-test
  ctypes
  ctypes-foreign
  signal-lg))
