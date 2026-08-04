# Crista

[![API documentation](https://img.shields.io/badge/API-documentation-blue)](https://akirak.github.io/crista/crista/)

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

Crista is tested against the following conformance suites:

- [Web Platform Tests](CONTRIBUTING.md#web-platform-tests)
- [Autobahn Testsuite](CONTRIBUTING.md#autobahn-websocket-conformance-tests)

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

WebSocket handlers use the same direct style. Returning `Response.websocket`
performs an RFC 6455 upgrade; the session API assembles fragmented messages,
validates UTF-8, answers pings, and performs the closing handshake:

```ocaml
let handler request =
  if Request.path request = "/socket" then
    Response.websocket (fun socket ->
      let rec echo () =
        match Websocket.receive socket with
        | Some (Websocket.Text text) ->
            Websocket.send_text socket text;
            echo ()
        | Some (Websocket.Binary data) ->
            Websocket.send_binary socket data;
            echo ()
        | None -> ()
      in
      echo ())
  else Response.empty 404
```

## Build and test

```sh
nix develop -c dune build
nix develop -c dune runtest
nix develop -c dune exec crista -- --bind 127.0.0.1 --port 8080
```

`Connection.Make` can be used to add another byte-stream transport.
