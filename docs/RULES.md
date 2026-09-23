# Backend Rules

_Backend only. Frontend rules: [`web/docs/RULES.md`](../web/docs/RULES.md)._

`MUST` is a rule with a cost behind it; `SHOULD` is a strong default. `observed` means the
codebase already does it everywhere. Structure: [`ARCHITECTURE.md`](ARCHITECTURE.md).
Rationale: [`DESIGN.md`](DESIGN.md). Traps: [`MEMORY.md`](MEMORY.md).

## Layering

- **R-01 MUST** A target imports only targets below it; the domain imports nothing.
- **R-02 MUST** Business rules live in `DashboardDomain` — never in a controller, a CLI command
  or an MCP tool, or three surfaces grow three versions of the same rule.
- **R-03 MUST** A new capability is a command-protocol method with a local and a remote
  implementation, never a route that talks to a store (D-05).
- **R-04 MUST** `WorkspaceStores.factory` stays the only branch on `StorageKind`.
- **R-05 MUST** Wire DTOs stay in `DashboardAPI` and are never domain types (D-06).
- **R-06 MUST** Register anything with a lifetime in `DashboardRuntime.register` and tear it
  down through `ShutdownHooks`; a service created inline leaks in one of the two roots.
- **R-07 MUST** Clock, ids, home and logger come from `@Dependency` — never `Date()`, `UUID()`
  or the environment. It is the only reason the tests are deterministic.

## Swift

- **R-08 MUST** Swift 6 language mode, strict concurrency; shared mutable state is an actor.
- **R-09 MUST** `any` for existentials in declarations and parameters.
- **R-10 MUST** No force-unwrap or `try!` without a comment saying why it cannot fail — a trap
  in the server takes the event socket with it.
- **R-11 SHOULD** `let` over `var`, `struct` over `class`, `guard` for early exits; it is what
  makes `Sendable` free. _(observed)_
- **R-12 SHOULD** One error type per module, mapped once at the edge (D-07).
- **R-13 SHOULD** Name a protocol for what it is (`WorkspaceStore`), an implementation for how
  (`KanbanJSONStore`, `RemoteBoardCommands`). No `Protocol`, `Impl` suffixes. _(observed)_
- **R-14 SHOULD** Comment only what the code cannot say: an invariant, a workaround, a ceiling.
- **R-15 SHOULD** Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and
  its upgrade path.

## Tests

- **R-16 MUST** Swift Testing (`@Test`, `#expect`, `#require`); no XCTest. _(observed, 40 files)_
- **R-17 MUST** A new store runs `StoreContract` — it is what keeps the storage kinds
  interchangeable.
- **R-18 MUST** Domain logic ships with a test in the matching test target.
- **R-19 SHOULD** Test AI changes against `FakeProvider`: no key, no network, no subscription.
- **R-20 SHOULD** Pin `\.now` and `\.uuid` rather than asserting loosely.

## Data and secrets

- **R-21 MUST** Every write to a project file, settings, config or credentials goes through
  `AtomicFile`.
- **R-22 MUST** Never delete a user file. Unregistering forgets a path; a conversion keeps the
  previous file.
- **R-23 MUST** Never write a secret to `config.yaml`, return one from the API, or log one.
- **R-24 MUST** Preserve unknown sections of `kanban.json` on read and write.
- **R-25 MUST** One connection per SQLite file; do not widen the pool or the event-loop group
  to fix a timeout — it reintroduces the `SQLITE_BUSY` deadlock (D-16).

## AI

- **R-26 MUST** Board text reaches the model as delimited data under the safety prompt, and the
  prompt order is fixed. A card is untrusted input.
- **R-27 MUST** Validate a draft before it leaves `AssistantService`; reject with
  `AI_BAD_OUTPUT` rather than passing a malformed one through.
- **R-28 MUST** A partial draft contains only values the model produced; never complete a
  truncated token by guessing.
- **R-29 MUST** Nothing reaches a board without an explicit user action (D-09).
- **R-30 SHOULD** A new vendor is a kind plus a factory; a new module only when it needs its own
  sign-in.
- **R-31 MUST** Never expose settings, providers, storage switching or credentials as MCP tools.

## Tooling, CI, Git

- **R-32 MUST** No new third-party dependency without asking first.
- **R-33 MUST** Keep the package building and testing on macOS and Linux.
- **R-34 MUST** Run `mise run check` (or `backend:test` plus `backend:test:linux`) before
  calling something done, and report failures instead of hiding them.
- **R-35 MUST** Run `npx prettier --write` on any Markdown you touch.
- **R-36 SHOULD** Update `README.md` and `website/docs/` with the code; run
  `mise run docs:build` when links move.
- **R-37 MUST** Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`,
  `perf:`, `ci:`).
- **R-38 MUST** Never `git push` or force-push without being asked.

## When a rule blocks you

The reason is the rule; the wording is a summary. If the reason still applies, take the longer
path — most of these exist because the short one was taken once. If it does not, say so in the
change: the rule, why it does not hold, what you did instead. Never satisfy a rule
cosmetically: a test that asserts nothing, a comment that repeats the code, a `try!` with a
comment that explains nothing.
