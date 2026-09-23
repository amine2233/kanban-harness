# Backend Design Decisions

_Backend only. UI/UX design lives in [`web/docs/DESIGN.md`](../web/docs/DESIGN.md) and [`website/docs/web/`](../website/docs/web/)._

Decisions already made and paid for. Structure: [`ARCHITECTURE.md`](ARCHITECTURE.md). Rules
they imply: [`RULES.md`](RULES.md). Do not reopen one without a written reason.

## D-01 The server is the single writer

Three surfaces can change the same board, and `kanban-rs` can edit the file behind all of
them. When a server runs, everything goes through it and it emits one event per mutation.
**Not:** per-surface writers with a watcher to reconcile — concurrent writers to one JSON file
have no safe merge. **Cost:** the CLI and MCP must probe for a server and bind remote
implementations.

## D-02 Files are the source of truth, hand edits win

Configuration and project data are read on every request; nothing is cached across requests,
nothing needs a restart. **Not:** an in-memory authority with periodic flush, which turns a
hand edit into a conflict. **Cost:** a file access per read.

## D-03 `kanban.json` is the kanban-rs v18 format, not ours

The JSON store writes their envelope, sub-task links are `graph.spawns` edges, unmodelled
sections ride along untouched. **Not:** a private format with an importer, which strands the
user on this tool. **Cost:** a new feature must fit that envelope, and a round trip must never
drop an unknown section.

## D-04 Two storage kinds behind one protocol, proven by one contract test

`Workspace` is the only model; both stores implement `WorkspaceStore`, both pass
`StoreContract`, and a JSON → SQLite → JSON test proves the round trip.
`WorkspaceStores.factory` is the only branch on storage kind. **Not:** a translation layer
between two models, which drift. **Cost:** none noticeable — a switch is load-then-save.

## D-05 Command protocols, bound local or remote at composition time

`DashboardService` declares the protocols, `DashboardClient` implements them over HTTP, call
sites see only the protocol. **Not:** an `if server != nil` at each call site, or a separate
HTTP-only CLI. **Cost:** a new capability means a protocol method and two implementations.

## D-06 Wire shapes copied from kanban-api

snake_case, explicit nulls, paginated lists; `DashboardAPI` owns the DTOs and they are not
domain types. **Not:** serialising domain types, where every rename breaks clients. **Cost:** a
DTO layer to keep in sync.

## D-07 One error envelope, built in middleware

Errors travel as their own types; `ApiErrorMiddleware` maps them once to `{code, message}` plus
status and `X-Request-Id`. **Not:** per-route mapping, which drifts and leaks internals.

## D-08 Drafts stream, and partial drafts never invent a value

The provider emits text and usage; `AssistantService` turns it into stages, partials and a
result, and the JSON completer drops any token it cannot finish. **Not:** waiting for the whole
response, or guessing a truncated enum. **Cost:** a test that cuts a draft at every character
offset to prove no prefix invents a value.

## D-09 The assistant proposes, a person disposes

A draft becomes cards only on an explicit action; board tools given to a drafting agent are
read-only. **Not:** auto-creating confident drafts. **Cost:** the draft travels to the client
and back, which also makes sub-task creation one atomic call.

## D-10 Board text is data, never instructions

Board content is delimited under a system prompt that forbids treating it as instructions; the
final draft is validated or rejected with `AI_BAD_OUTPUT`; `claude_code` runs with tools
disabled and no session persistence. **Not:** trusting the model to ignore injected text.
**Cost:** a fixed prompt order that agent files cannot loosen.

## D-11 One provider abstraction, Claude Code the deliberate exception

Everything goes through AnyLanguageModel except `claude_code`, which drives the headless CLI.
**Not:** a client per vendor, nor an HTTP shim over Claude Code. **Cost:** Claude Code carries
its own parsing quirks — and is the only vendor reporting exact cost.

## D-12 One module per vendor that has a sign-in

`DashboardOAuth` owns PKCE and the code exchange; each vendor module owns its URLs, factory and
`ProviderSignIn`. **Not:** a vendor switch inside one OAuth module. **Cost:** one target per
vendor.

## D-13 Secrets live outside the config file and outside the API

Settings in `config.yaml`, secrets in `credentials.json` (`0600`) or in
`MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY`, which is never written back; the API reports
`has_api_key`. **Not:** keys in the config file (the earlier design, migrated on next save), or
a keychain as the only backend, which Linux lacks. **Cost:** three resolution sources in a
fixed order.

## D-14 Writes are atomic, and unregistering deletes nothing

Every write goes through `AtomicFile` (temp file, rename); removing a project forgets a path.
**Not:** in-place writes with a backup. **Cost:** a rename per write.

## D-15 cascade-kit for lifetimes, `@Dependency` for ambient values

The container holds anything with a lifetime, registered once and shut down in reverse;
`@Dependency` holds `\.now`, `\.uuid`, `\.home`, `\.logger`; the server layers a per-request
container. **Not:** a hand-rolled locator, nor a `Context` struct threaded through every call.
**Cost:** a service reading the clock directly cannot be tested — so it is a bug.

## D-16 One SQLite connection per database file

A multi-loop event-loop group gives one connection per loop on the same file; two writers hit
`SQLITE_BUSY` and sqlite-nio retries forever while holding a thread, which looks like a pool
deadlock. `SQLiteDatabase` pins one event loop per file; the thread count is
`DatabaseConfig.threadPoolSize` (default 2). **Not:** more threads or a bigger pool, which
makes it worse. **Cost:** writes to one file are serialised; real parallelism would need WAL
and a bounded busy handler upstream. (`SQLiteDatabase.swift`, commit `1920634`)

## D-17 MCP exposes boards and cards, nothing else

Settings, providers, storage switching and credentials are not tools; stdio is the default and
the HTTP endpoint is localhost-only. **Not:** mirroring the whole API. **Cost:** an agent
cannot configure the product, only use it.

## D-18 No authentication, by design and by default

No accounts, no tokens; loopback unless the user opts out; CORS origins read live. **Not:** a
token check that is theatre on a loopback socket and insufficient for a real deployment.
**Cost:** exposing the server on a network is the user's decision, documented as such.

Sources: `README.md`, `website/docs/`, `docs/conceptions/`, `Package.swift`, `Sources/`.
