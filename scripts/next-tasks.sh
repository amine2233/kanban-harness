#!/usr/bin/env bash
# Build order for docs/TASKS.md, from the `· blocked by` field each task already carries.
# Fails loudly on a circular `blocked by`.
set -euo pipefail

tasks="${1:-docs/TASKS.md}"

ids() {
  grep -oE '\*\*T-[0-9]+ \([SML]\)\*\*' "$tasks" | grep -oE 'T-[0-9]+' | sort -u
}

# "<blocker> <task>" pairs. No self-edges: tsort treats them as cycles and
# silently reorders around them. A bullet is joined with its wrapped
# continuation lines first, or a `· T-nn` that prettier pushed onto the next
# line is never seen.
edges() {
  awk '
    function emit(rec,   h, rest, d) {
      if (!match(rec, /\*\*T-[0-9]+ \([SML]\)\*\*/)) return
      h = substr(rec, RSTART, RLENGTH); sub(/^\*\*/, "", h); sub(/ .*/, "", h)
      rest = rec
      while (match(rest, /· T-[0-9]+/)) {
        d = substr(rest, RSTART, RLENGTH); sub(/^· /, "", d)
        if (d != h) print d, h
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    /^- \*\*T-[0-9]+ \([SML]\)\*\*/ { emit(buf); buf = $0; next }
    /^#/                                { emit(buf); buf = ""; next }
    { buf = buf " " $0 }
    END { emit(buf) }
  ' "$tasks"
}

ordered=$(edges | tsort)                      # non-zero + message on a cycle
# Tasks in no dependency at all: nothing blocks them, they block nothing.
comm -23 <(ids) <(printf '%s\n' "$ordered" | sort -u)
printf '%s\n' "$ordered"
