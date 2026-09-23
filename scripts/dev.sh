#!/usr/bin/env bash
# Starts the backend and the Vite dev server together. Frees ports held by
# stale copies of our own servers, fails loudly when something else holds them,
# and restarts a backend that dies while the web server is up.
# Usage: scripts/dev.sh [--lan]
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${MVP_DASHBOARD_PORT:-5175}"
WEB_PORT="${MVP_DASHBOARD_WEB_PORT:-5173}"
HOST_FLAG=()
[[ "${1:-}" == "--lan" ]] && HOST_FLAG=(--host 0.0.0.0)

listener() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -Fpc 2>/dev/null; }

free_port() { # port, name-of-our-process
  local info pid cmd
  info="$(listener "$1")" || true
  [[ -z "$info" ]] && return 0
  pid="$(sed -n 's/^p//p' <<<"$info" | head -1)"
  cmd="$(sed -n 's/^c//p' <<<"$info" | head -1)"
  if [[ "$cmd" == "$2"* ]]; then
    echo "port $1 held by a stale $cmd (pid $pid) — stopping it"
    kill "$pid" && sleep 1
  else
    echo "port $1 is taken by '$cmd' (pid $pid). Stop it or set MVP_DASHBOARD_PORT / MVP_DASHBOARD_WEB_PORT." >&2
    exit 1
  fi
}

free_port "$PORT" dashboard
free_port "$WEB_PORT" node

BIN=.build/debug/dashboard
[[ -x "$BIN" ]] || { echo "backend not built — run: mise run backend:build" >&2; exit 1; }

start_backend() { "$BIN" serve --port "$PORT" & BACKEND=$!; STARTED=$SECONDS; }

start_backend
trap 'kill $BACKEND ${WEB:-} 2>/dev/null || true' EXIT
trap 'exit 130' INT TERM

for _ in $(seq 1 50); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/api/health" && break
  kill -0 $BACKEND 2>/dev/null || { echo "backend exited — see the error above" >&2; exit 1; }
  sleep 0.2
done
echo "backend ready on http://127.0.0.1:$PORT"

pnpm dev --port "$WEB_PORT" "${HOST_FLAG[@]}" &
WEB=$!

# Keep the backend alive for as long as the web server runs. Bounded: five
# restarts in a row, a second apart, so a backend that dies on startup cannot
# spin; staying up 30s clears the count. Ctrl-C hits the traps above instead.
fails=0
while kill -0 "$WEB" 2>/dev/null; do
  sleep 1
  if kill -0 "$BACKEND" 2>/dev/null; then continue; fi
  code=0
  wait "$BACKEND" || code=$?
  if [[ $code -eq 0 ]]; then
    echo "backend exited cleanly — stopping the web server too" >&2
    exit 0
  fi
  if (( SECONDS - STARTED >= 30 )); then fails=0; fi
  fails=$((fails + 1))
  if (( fails > 5 )); then
    echo "backend exited ($code) 5 times in a row — giving up" >&2
    exit 1
  fi
  echo "backend exited ($code) — restarting ($fails/5)" >&2
  sleep 1
  start_backend
done

wait "$WEB"
