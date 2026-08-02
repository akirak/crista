(lang dune 3.21)

(name mitochondria)

(generate_opam_files true)

(package
 (name mitochondria)
 (synopsis "A small direct-style HTTP/1 server framework")
 (description "An HTTP/1.0 and HTTP/1.1 server framework for Miou and Picos")
 (depends
  (ocaml (>= 5.2))
  picos
  picos_io
  miou
  parseff
  (alcotest :with-test))
 (tags
  (http server miou picos)))
