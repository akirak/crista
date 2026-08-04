# Instructions for the developer
At present, this project doesn't expect contributions. This guide is relevant
only to the author/developer/maintainer of this project, so it has been split
out from the readme.

## Web Platform Tests

The testharness test in `wpt/crista.any.js` exercises the browser Fetch API
against a live Crista server. It covers GET and HEAD requests, POST bodies,
redirects, CORS, and concurrent requests. With a local
[web-platform-tests](https://github.com/web-platform-tests/wpt) checkout and a
supported browser installed, run:

```sh
nix develop -c dune build
WPT_ROOT=/path/to/wpt BROWSER=chrome ./scripts/run-wpt.sh
```

The runner temporarily copies the test into the WPT checkout, starts Crista on
`127.0.0.1:8080`, invokes `wpt run`, and then stops the server and removes the
copied test. Pass any additional `wpt run` options after the script name.

## Autobahn WebSocket conformance tests

The Crista binary exposes a WebSocket echo endpoint at
`ws://127.0.0.1:18181/__crista/websocket`. With Docker available, run the core
RFC 6455 client cases from the
[Autobahn Testsuite](https://github.com/crossbario/autobahn-testsuite) against
this endpoint. The optional permessage-deflate cases are excluded because
Crista does not negotiate that extension:

```sh
nix develop -c just autobahn
```

The generated HTML report is written to `_build/autobahn/index.html`. Set
`AUTOBAHN_IMAGE` to pin a particular test-suite image and
`AUTOBAHN_REPORT_DIR` to change the report directory.
