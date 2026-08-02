# Mitochondria

Mitochondria is a small direct-style HTTP/1.0 and HTTP/1.1 server framework for
OCaml 5. Its protocol core is transport-independent, with a ready-to-run Miou
backend. Request syntax is parsed with Parseff.

```ocaml
open Mitochondria

let router = Router.create ()

let () =
  Router.get "/hello" (fun _ -> Response.text "Hello!\n") router;
  Miou_server.run ~port:8080 (Router.route router)
```

The server supports persistent connections, pipelining, fixed-length and
chunked request bodies, `Expect: 100-continue`, HEAD responses, and configurable
header/body limits. Ambiguous Content-Length and Transfer-Encoding combinations
are rejected before dispatch.

## Build and test

```sh
nix develop -c dune build
nix develop -c dune runtest
nix develop -c dune exec mitochondria -- --bind 127.0.0.1 --port 8080
```

`Connection.Make` can be used to add another byte-stream transport.

## Web Platform Tests

The WPT testharness test in `wpt/mitochondria.any.js` exercises browser Fetch
against a live Mitochondria process: GET, POST bodies, HEAD, redirects, CORS,
and concurrent requests. With a local
[web-platform-tests](https://github.com/web-platform-tests/wpt) checkout and a
supported browser installed, run:

```sh
nix develop -c dune build
WPT_ROOT=/path/to/wpt BROWSER=chrome ./scripts/run-wpt.sh
```

The runner temporarily copies the test into the WPT checkout, starts the server
on `127.0.0.1:8080`, invokes `wpt run`, then cleans up both. Additional
`wpt run` options may be passed after the script name.
