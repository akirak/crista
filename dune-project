(lang dune 3.21)

(name crista)

(generate_opam_files true)

(package
 (name crista)
 (authors "Akira Komamura <akira.komamura@gmail.com>")
 (maintainers "Akira Komamura <akira.komamura@gmail.com>")
 (homepage https://github.com/akirak/crista)
 (synopsis "A minimalistic HTTP server framework for OCaml 5")
 (description "A small direct-style server framework for OCaml 5 built on top of the Miou scheduler")
 (depends
  (ocaml (>= 5.3))
   picos
   picos_io
   miou
   parseff
  (alcotest :with-test)
  (odig :with-test)
  (routes :with-test))
 (tags
  (http server miou picos)))

(license ISC)
