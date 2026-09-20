#!/usr/bin/env bash
# Quick environment check: toolchain, build outputs, dev ports.
cd "$(dirname "$0")/.."
echo "node $(node -v 2>/dev/null || echo missing)  pnpm $(pnpm -v 2>/dev/null || echo missing)  swift $(swift --version 2>/dev/null | head -1 | grep -o 'version [0-9.]*' | cut -d' ' -f2)"
[[ -x backend/.build/debug/dashboard ]] && echo "backend binary: ok" || echo "backend binary: missing -> mise run backend:build"
[[ -d node_modules ]] && echo "node_modules: ok" || echo "node_modules: missing -> pnpm install"
for p in "${MVP_DASHBOARD_PORT:-5175}" "${MVP_DASHBOARD_WEB_PORT:-5173}"; do
  l=$(lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -1)
  if [[ -z "$l" ]]; then echo "port $p: free"; else echo "port $p: IN USE by $(awk '{print $1" (pid "$2")"}' <<<"$l") -> mise run stop"; fi
done
echo "home: ${MVP_DASHBOARD_HOME:-<default>}"
