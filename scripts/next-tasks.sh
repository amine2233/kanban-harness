#!/usr/bin/env bash
# Build order for docs/TASKS.md, from the `· blocked by` field each task already carries.
# Fails loudly on a circular `blocked by`.
set -euo pipefail

tasks="${1:-docs/TASKS.md}"

ids() {
  grep -oE '\*\*T-[0-9]+ \([SML]\)\*\*' "$tasks" | grep -oE 'T-[0-9]+' | sort -u
}

# "<blocker> <task>" pairs. No self-edges: tsort treats them as cycles and
# silently reorders around them.
edges() {
  awk 'match($0, /\*\*T-[0-9]+ \([SML]\)\*\*/) {
    h = substr($0, RSTART, RLENGTH); sub(/^\*\*/, "", h); sub(/ .*/, "", h)
    rest = $0
    while (match(rest, /· T-[0-9]+/)) {
      d = substr(rest, RSTART, RLENGTH); sub(/^· /, "", d)
      if (d != h) print d, h
      rest = substr(rest, RSTART + RLENGTH)
    }
  }' "$tasks"
}

ordered=$(edges | tsort)                      # non-zero + message on a cycle
# Tasks in no dependency at all: nothing blocks them, they block nothing.
comm -23 <(ids) <(printf '%s\n' "$ordered" | sort -u)
printf '%s\n' "$ordered"
