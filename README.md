# Crista

> [!WARNING]
> This project was originally developed for internal use and remains
> experimental. Its APIs are
> subject to change, and there is no guarantee of ongoing maintenance. Use
> it at your own risk.

Crista is a small direct-style HTTP/1.0 and HTTP/1.1 server framework for
OCaml 5. Its goals are to:

- Allow applications to use effects in their logic.
- Remain router-agnostic, so applications can use, for example, the
  [routes](https://github.com/anuragsoni/routes) library.
- Support features needed to build frontend applications: compression, WebSocket, SSE, etc. Strict conformance to their specs.
- Support [Picos](https://github.com/ocaml-multicore/picos) for concurrent
  programming.

At present, the server is built on top of the
[miou](https://github.com/robur-coop/miou) scheduler.

> [!NOTE]
> The name comes from cristae, the folds inside mitochondria where ATP
> production occurs.

## Usage example

```ocaml
open Crista

let router =
  Routes.one_of
    [ Routes.((s "hello" /? nil) @--> fun request ->
        Response.text ("Hello from " ^ request.Request.target ^ "!\n")) ]

let handler request =
  match Routes.match' router ~target:(Request.path request) with
  | Routes.FullMatch route | Routes.MatchWithTrailingSlash route -> route request
  | Routes.NoMatch -> Response.text ~status:404 "Not found\n"

let () =
  Miou_server.run ~port:8080 handler
```

Crista does not prescribe a routing library: a server accepts a plain
`Request.t -> Response.t` handler. The example uses the optional `routes`
library, while applications can plug in any dispatcher with that shape.

The server supports persistent connections, pipelining, fixed-length and
chunked request bodies, `Expect: 100-continue`, HEAD responses, and configurable
header/body limits. Ambiguous Content-Length and Transfer-Encoding combinations
are rejected before dispatch.

## Build and test

```sh
nix develop -c dune build
nix develop -c dune runtest
nix develop -c dune exec crista -- --bind 127.0.0.1 --port 8080
```

`Connection.Make` can be used to add another byte-stream transport.

## Web Platform Tests

The WPT testharness test in `wpt/crista.any.js` exercises browser Fetch
against a live Crista process: GET, POST bodies, HEAD, redirects, CORS,
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
