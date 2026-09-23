#!/usr/bin/env bash
# Exercises the restart loop of scripts/dev.sh against a fake backend, a fake
# `pnpm` and a fake `curl`, in a throwaway copy of the tree. Run it by hand
# after touching dev.sh — it takes about 20 seconds.
# Usage: scripts/dev-restart-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT="$PWD/scripts/dev.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/.build/debug" "$TMP/bin"
cp "$SCRIPT" "$TMP/scripts/dev.sh"

cat >"$TMP/.build/debug/dashboard" <<'EOF'
#!/bin/sh
n=$(($(cat "$COUNT") + 1)); echo "$n" >"$COUNT"
[ "$n" -le "$FAIL_UNTIL" ] && exit 3
exec sleep 60
EOF
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/curl"
printf '#!/bin/sh\nexec sleep 60\n' >"$TMP/bin/pnpm"
chmod +x "$TMP/.build/debug/dashboard" "$TMP/bin/curl" "$TMP/bin/pnpm"

export PATH="$TMP/bin:$PATH" COUNT="$TMP/count"
export MVP_DASHBOARD_PORT=57511 MVP_DASHBOARD_WEB_PORT=57512

run() { # fail-until, seconds to wait -> $LOG, $LAUNCHES, $STILL_UP
  echo 0 >"$COUNT"
  FAIL_UNTIL="$1" "$TMP/scripts/dev.sh" >"$TMP/log" 2>&1 &
  local pid=$!
  sleep "$2"
  STILL_UP=no; kill -0 "$pid" 2>/dev/null && STILL_UP=yes
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  LOG="$(cat "$TMP/log")"; LAUNCHES="$(cat "$COUNT")"
}

fail() { echo "FAIL: $1"; echo "--- log ---"; echo "$LOG"; exit 1; }

run 2 8
[[ "$LAUNCHES" == 3 ]] || fail "expected 3 backend launches, got $LAUNCHES"
[[ "$LOG" == *"restarting (1/5)"* && "$LOG" == *"restarting (2/5)"* ]] || fail "missing restart lines"
[[ "$LOG" != *"(3/5)"* ]] || fail "restarted a backend that was still running"
[[ "$STILL_UP" == yes ]] || fail "dev.sh gave up while the backend was healthy"
echo "ok — a crashing backend comes back, a healthy one is left alone"

run 99 16
[[ "$LAUNCHES" == 6 ]] || fail "expected 6 launches (1 + 5 restarts), got $LAUNCHES"
[[ "$LOG" == *"giving up"* ]] || fail "no bound: the restart loop never gave up"
[[ "$STILL_UP" == no ]] || fail "dev.sh kept spinning after 5 failures"
echo "ok — a backend that always fails stops after 5 restarts"
