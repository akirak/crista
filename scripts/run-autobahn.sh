#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${AUTOBAHN_PORT:-18181}
REPORT_DIR=${AUTOBAHN_REPORT_DIR:-"$ROOT/_build/autobahn"}
IMAGE=${AUTOBAHN_IMAGE:-crossbario/autobahn-testsuite}

if [[ "$PORT" != 18181 ]]; then
  echo "The checked-in Autobahn configuration uses port 18181." >&2
  echo "Set AUTOBAHN_PORT=18181 or update autobahn/fuzzingclient.json." >&2
  exit 2
fi

command -v docker >/dev/null || {
  echo "docker is required to run the Autobahn test suite" >&2
  exit 2
}

mkdir -p "$REPORT_DIR"
dune build bin/main.exe

"$ROOT/_build/default/bin/main.exe" --bind 127.0.0.1 --port "$PORT" \
  >"$REPORT_DIR/server.log" 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

ready=false
for _attempt in $(seq 1 50); do
  status=$(curl --fail --silent "http://127.0.0.1:$PORT/__crista/status" || true)
  if [[ "$status" == '{"status":"ok"}' ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Crista stopped before Autobahn could connect" >&2
    exit 1
  fi
  sleep 0.1
done

if [[ "$ready" != true ]]; then
  echo "Crista did not become ready on port $PORT" >&2
  exit 1
fi

docker run --rm --network host \
  --volume "$ROOT/autobahn:/config:ro" \
  --volume "$REPORT_DIR:/reports" \
  "$IMAGE" \
  wstest -m fuzzingclient -s /config/fuzzingclient.json

if grep -E -q \
  '"behavior(Close)?"[[:space:]]*:[[:space:]]*"(FAILED|NON-STRICT)"' \
  "$REPORT_DIR/index.json"; then
  echo "Autobahn reported failed or non-strict cases; see $REPORT_DIR/index.html" >&2
  exit 1
fi

echo "Autobahn report: $REPORT_DIR/index.html"
