<!--
Title: conventional commit — `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `test:`, `chore:`.
`check:merge_request:title` lints it and comments on this PR.
-->

## What and why

<!-- The problem, not the diff. The diff already says what changed. -->

## Chain

<!-- Where this comes from. Delete the lines that do not apply. -->

- Decision: `docs/conceptions/<note>.md`
- Task: `T-nn` in the conception note's `## Tasks` (or `web/docs/TASKS.md`)
- Series: `docs/series/<slug>.md`

## Checks

- [ ] `mise run check` is green
- [ ] Each commit stands alone: it builds and passes its own check
- [ ] The commit message says _why_, not _what_
- [ ] The task's line removed from its note's `## Tasks`, or marked `· dropped: <why>`
- [ ] Facts live in one place; nothing copied between docs

## Not in this PR

<!-- What a reviewer will expect and not find, and where it lives instead. -->
