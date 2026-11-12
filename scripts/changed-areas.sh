#!/usr/bin/env bash
# Which areas a diff touches: prints `backend=`, `web=` and `website=` lines,
# each `true` or `false`. CI and factory/checks.sh both read it, so the rule
# for "what needs checking" has one home.
#
#   scripts/changed-areas.sh <from> <to>
#
# An empty <from> means the range is unknown (a force-push, a branch's first
# commit, a rewritten history), and "we cannot tell" must read as "run
# everything".
set -euo pipefail

from="${1:-}"
to="${2:-HEAD}"

if [ -z "$from" ]; then
  echo 'no usable diff range; running every area' >&2
  changed=''
  unknown=1
else
  changed="$(git diff --name-only "$from" "$to")"
  unknown=0
  printf '%s\n' "$changed" | sed 's/^/  /' >&2
fi

# ci.yml and this script are in all three: editing either reruns everything,
# which is the cheap insurance against a filter that silently stops matching.
# $2 is an optional exclusion, applied before the include match, so a path that
# only looks like an area does not select it.
area() {
  if [ "$unknown" = '1' ]; then echo 'true'; return; fi
  if printf '%s\n' "$changed" | grep -Ev "${2:-^$}" | grep -Eq "$1"; then
    echo 'true'
  else
    echo 'false'
  fi
}

always='|^\.github/workflows/ci\.yml$|^scripts/changed-areas\.sh$'
shared="|^package\.json$|^pnpm-lock\.yaml$|^pnpm-workspace\.yaml\$${always}"

echo "backend=$(area "^Sources/|^Tests/|^Package\.(swift|resolved)$|^mise\.toml\$${always}")"
# `web/docs/` and `web/*.md` are documentation: eslint, tsc, vitest and the
# build cannot fail on them, and the check that can — prettier — runs on every
# change regardless of area.
echo "web=$(area "^web/$shared" '^web/(docs/|[^/]*\.md$)')"
echo "website=$(area "^website/|^docs/conceptions/$shared")"
