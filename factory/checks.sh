#!/usr/bin/env bash
# The repo's checks. Exit 0 only when the branch is fit to review.
#
# The gate runs this from the main checkout with the job's worktree as the
# working directory. Only the areas the branch touches since origin/main are
# checked — the same rule CI uses, from scripts/changed-areas.sh. The backend
# bar includes Linux because macOS stays green while Linux fails.
set -euo pipefail

base="$(git merge-base origin/main HEAD || true)"
areas="$(scripts/changed-areas.sh "$base" HEAD)"
echo "$areas"
on() { printf '%s\n' "$areas" | grep -qx "$1=true"; }

pnpm install --frozen-lockfile --prefer-offline
pnpm format:check

if on backend; then
  mise run check:format
  mise run backend:test
  mise run backend:test:linux
fi

if on web; then
  pnpm lint
  pnpm typecheck
  pnpm test
  pnpm build
fi

if on website; then
  pnpm --filter website build
fi
