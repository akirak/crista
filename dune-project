(lang dune 3.21)

(name crista)

(generate_opam_files true)

(package
 (name crista)
 (authors "Akira Komamura <akira.komamura@gmail.com>")
 (maintainers "Akira Komamura <akira.komamura@gmail.com>")
 (homepage https://github.com/akirak/crista)
 (synopsis "A minimalistic HTTP server framework for OCaml 5")
 (description "A small scheduler-neutral direct-style HTTP server framework for OCaml 5")
 (depends
  (ocaml (>= 5.3))
   parseff
  (alcotest :with-test)
  (odig :with-doc)
  (routes :with-test))
 (tags
  (http server)))

(package
 (name crista-eio)
 (authors "Akira Komamura <akira.komamura@gmail.com>")
 (maintainers "Akira Komamura <akira.komamura@gmail.com>")
 (homepage https://github.com/akirak/crista)
 (synopsis "Eio backend for Crista")
 (description "Run Crista HTTP handlers using Eio")
 (depends
  (ocaml (>= 5.3))
  (crista (= :version))
  eio
  (odig :with-doc))
 (tags
  (http server eio)))

(package
 (name crista-picos)
 (authors "Akira Komamura <akira.komamura@gmail.com>")
 (maintainers "Akira Komamura <akira.komamura@gmail.com>")
 (homepage https://github.com/akirak/crista)
 (synopsis "Picos backend for Crista")
 (description "Run Crista HTTP handlers using a Picos-compatible scheduler")
 (depends
  (ocaml (>= 5.3))
  (crista (= :version))
  picos
  picos_io
  (odig :with-doc))
 (tags
  (http server picos)))

(package
 (name crista-miou)
 (authors "Akira Komamura <akira.komamura@gmail.com>")
 (maintainers "Akira Komamura <akira.komamura@gmail.com>")
 (homepage https://github.com/akirak/crista)
 (synopsis "Miou backend for Crista")
 (description "Run Crista HTTP handlers using Miou")
 (depends
  (ocaml (>= 5.3))
  (crista (= :version))
  miou
  miou_unix
  (odig :with-doc))
 (tags
  (http server miou)))

(license ISC)
