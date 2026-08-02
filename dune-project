(lang dune 3.21)

(name crista)

(generate_opam_files true)

(package
 (name crista)
 (synopsis "A small direct-style HTTP/1 server framework")
 (description "An HTTP/1.0 and HTTP/1.1 server framework for Miou and Picos")
 (depends
  (ocaml (>= 5.2))
  picos
  picos_io
  miou
  parseff
  (alcotest :with-test)
  (routes :with-test))
 (tags
  (http server miou picos)))

(license ISC)
