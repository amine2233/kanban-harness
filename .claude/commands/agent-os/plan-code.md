---
description: Decompose a feature into a kernel-style patch series you implement by hand
argument-hint: [conception note path | PRD or TASKS id | feature sentence]
---

Target: $ARGUMENTS

You decompose work into a patch series. You do not write the code: the series is the
deliverable, the patches are written by hand afterwards. This is the Linux kernel split —
the reflection is yours, the implementation is not.

If the target is empty, ask for it and stop.

# Before anything

Read, in this order:

1. The target: a conception note (`docs/conceptions/*.md`), the requirement behind an id in
   `docs/PRD.md` / the entry in `docs/TASKS.md`, or, for a plain sentence, whatever in
   `docs/` covers it.
2. `docs/ARCHITECTURE.md` — the layering each patch must respect.
3. `docs/RULES.md` — the constraints each patch must satisfy.
4. `docs/MEMORY.md` — the traps that make a naive decomposition wrong.
5. The code the series will touch.

**If the approach is not settled, stop and ask.** A series decomposes a decision that has
already been made; it does not make it. When the target is a sentence with no design note
behind it, say what is missing (an RFC in `docs/conceptions/`) and stop. When the note leaves
a real choice open, ask that one question and stop.

# Write exactly one file

`docs/series/<slug>.md`, where `<slug>` is the note's name or a short kebab-case name for the
feature. Create `docs/series/` if it is not there. Touch nothing else — never `Sources/`,
`Tests/`, `web/` or any other doc.

```markdown
# <feature> — patch series v1

_Target: <the note, id or sentence>. Implemented by hand; this file is the contract._

## Cover letter

**Problem.** What is broken or missing, in the user's terms.
**Design.** The approach, in three sentences, and the alternative that was rejected.
**Order.** Why the patches are in this order and not another.
**Not in this series.** What a reader would expect here and will not find, with where it
lives instead (`web/docs/TASKS.md` for client work, a later series, a decision still open).

## [1/N] <conventional commit subject, imperative, under 72 chars>

**What.** One logical change, one sentence.
**Touches.** Targets and files.
**Why.** What is impossible or broken without it.
**Check.** The command that fails before and passes after.
**Bisect.** What still builds and passes at this commit.

## [2/N] …
```

# Rules for the decomposition

- **One logical change per patch.** A subject that needs "and" is two patches.
- **Every patch stands alone.** It builds and passes `mise run backend:test` on its own; no
  patch needs a later one to compile. A patch that cannot do that is cut differently.
- **Refactor first, change second, always two patches.** A move mixed with a behaviour change
  is unreviewable.
- **Every patch names its check** — a specific test, not "run the suite". A patch with no
  possible check is called out as such in its `Check` line, with why.
- **The last patch is the one that turns it on.** Plumbing lands first, inert; the switch is
  its own small patch, so a revert is one commit.
- **Stop at the backend boundary.** Client work goes under "Not in this series" with a
  pointer to `web/docs/TASKS.md`.
- **Respect the layering.** A patch that adds a rule outside `DashboardDomain`, branches on
  `StorageKind` outside `WorkspaceStores.factory`, or adds a route without a command-protocol
  method is wrong before it is written — cite the rule (`R-nn`) in `Why` instead.
- **Prefer fewer patches.** Five real ones beat twelve ceremonial ones. Do not split what
  cannot be reviewed separately.
- Reuse the order the source note already fixed (its "Order of work" or "Implementation
  steps"); when you depart from it, say so in the cover letter.

# Finish

Run `npx prettier --write docs/series/<slug>.md`.

Then, in at most six lines: the patch count, the riskiest patch and why, anything the note
left open that you had to assume, and the command to start patch 1. Do not implement it.
