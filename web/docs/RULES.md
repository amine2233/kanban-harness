# Web App Rules

_Frontend only. Backend rules: [`docs/RULES.md`](../../docs/RULES.md)._

`MUST` has a cost behind it; `SHOULD` is a strong default. Structure:
[`ARCHITECTURE.md`](ARCHITECTURE.md). Rationale: [`DESIGN.md`](DESIGN.md). Traps:
[`MEMORY.md`](MEMORY.md).

## Layering

- **R-01 MUST** Respect the package layering; the ESLint block that rejects an import is the
  rule, not an obstacle.
- **R-02 MUST** Import a package by name (`@mvp/state`), never by path or by file.
- **R-03 MUST** Server state reaches a component only through the store. No `fetch`, no
  hand-written URL, no `axios` outside `@mvp/state` (D-01).
- **R-04 MUST** A new endpoint is an `injectEndpoints` file under `packages/state/src/api/`,
  exported from the package's `index.ts`, with its cache tags.
- **R-05 MUST** No `hk-*` or `ds-*` class outside `@mvp/design-system`; the app composes
  components (D-08).
- **R-06 MUST** Pure board logic goes to `@mvp/kanban-model`, never into a component.
- **R-07 SHOULD** A new app area is a plugin registered in `src/app/plugins.ts`, not a route
  added by hand (WEB-16).

## TypeScript and React

- **R-08 MUST** No `any` without a comment saying why; the rule is an error, not a warning.
- **R-09 MUST** ESM only; `import type` for types (`consistent-type-imports` is enforced).
- **R-10 MUST** Do not weaken `tsconfig.base.json` to make a change compile. If
  `exactOptionalPropertyTypes` rejects the code, the code is wrong.
- **R-11 SHOULD** Derive state rather than storing it; reset by `key`, never in an effect
  (D-14).
- **R-12 SHOULD** Put the decision in a pure `.ts` module next to the component and keep the
  `.tsx` rendering (D-09).
- **R-13 SHOULD** Every mutation has a visible pending state and an error path using
  `errorMessage(error)`; never swallow a rejection.

## Accessibility

- **R-14 MUST** Every mouse action has a keyboard-reachable equivalent — a drag also has arrow
  controls (WEB-05).
- **R-15 MUST** Interactive elements are real controls with an accessible name; a `div` with
  `onClick` is not one.
- **R-16 SHOULD** A control added inside a draggable card stops `mousedown` and `click`
  propagation, or it kills the drag ([`MEMORY.md`](MEMORY.md)).

## Tests

- **R-17 MUST** Vitest; UI tests stub the server with `stubApi()` from `@mvp/state/testing`,
  never by mocking hooks or preloading cache state (D-13).
- **R-18 MUST** Query by role, label or text — not by class, test id or component internals.
- **R-19 MUST** New pure modules ship with a test over plain data.
- **R-20 SHOULD** A bug fix lands with the test that would have caught it; the drag-and-drop
  regressions are the reason.

## Before calling it done

- **R-21 MUST** `pnpm format:check`, `pnpm lint`, `pnpm typecheck`, `pnpm test` — or
  `mise run web:check` plus `pnpm test`. Report failures instead of hiding them.
- **R-22 MUST** Keep `pnpm build` green; the type-check runs over project references, so a
  package can break the build without the app changing.
- **R-23 SHOULD** Update `website/docs/web/` when behaviour changes; it is what users read and
  it is already drifting.
- **R-24 MUST** No new dependency without asking; every one is also a `pnpm audit` gate in CI.
- **R-25 MUST** Conventional commits; never `git push` or force-push unasked.

## When a rule blocks you

The reason is the rule; the wording is a summary. If the reason still holds, take the longer
path. If it does not, say so in the change: the rule, why it does not apply, what you did
instead. Never satisfy one cosmetically — a test that renders and asserts nothing, an `any`
with a comment that explains nothing, a lint disable without a line saying why.
