#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${WPT_ROOT:-}" || ! -x "${WPT_ROOT}/wpt" ]]; then
  echo "Set WPT_ROOT to a web-platform-tests checkout." >&2
  exit 2
fi

browser="${BROWSER:-chrome}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="${WPT_ROOT}/mitochondria"
test_file="${test_dir}/mitochondria.any.js"

if [[ -e "${test_dir}" ]]; then
  echo "Refusing to replace existing ${test_dir}" >&2
  exit 2
fi

cleanup() {
  if [[ -n "${server_pid:-}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -f "${test_file}"
  rmdir "${test_dir}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir "${test_dir}"
cp "${project_root}/wpt/mitochondria.any.js" "${test_file}"

"${project_root}/_build/default/bin/main.exe" --bind 127.0.0.1 --port 8080 &
server_pid=$!

ready=false
for _ in $(seq 1 50); do
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    wait "${server_pid}"
    exit 1
  fi
  if command -v curl >/dev/null &&
    curl --fail --silent http://127.0.0.1:8080/__mitochondria/status >/dev/null; then
    ready=true
    break
  fi
  sleep 0.1
done

if [[ "${ready}" != true ]]; then
  echo "Mitochondria did not become ready on port 8080." >&2
  exit 1
fi

cd "${WPT_ROOT}"
./wpt run "${browser}" mitochondria/mitochondria.any.js "$@"
