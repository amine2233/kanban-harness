# Backend Memory

_Backend only. Frontend notes: [`web/docs/MEMORY.md`](../web/docs/MEMORY.md)._

Things that cost an afternoon once. When one stops being true, rewrite it. Rationale lives in
[`DESIGN.md`](DESIGN.md), rules in [`RULES.md`](RULES.md).

## Invariants

A `kanban.json` written here opens in `kanban-rs`; unknown sections survive a round trip;
JSON → SQLite → JSON loses nothing; unregistering deletes no file; a key from
`MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` never lands on disk. Each one is cheap to break in a
refactor that looks local. (`StoreContract.swift`, [`PRD.md`](PRD.md#data-contract))

## One SQLite connection per file, or the server deadlocks

A multi-loop event-loop group creates one connection per loop on the same file; two writers hit
`SQLITE_BUSY` and sqlite-nio's busy handler retries forever holding a thread-pool thread. It
surfaces as `[AsyncKit] Connection request timed out`, which looks like an exhausted pool — so
the instinct is to raise the pool size, which makes it worse. `SQLiteDatabase` pins one event
loop per file. (`SQLiteDatabase.swift`, commit `1920634`)

## The environment reaches the daemon, not the command

The daemon does the work, and it inherits the environment of whichever command happened to start
it. So `MVP_DASHBOARD_CLAUDE_BIN=… dashboard ai draft …` has no effect if a daemon is already
running for that home — the variable is read where the provider runs, which is the daemon. It
looks like the variable is ignored. Set it on every invocation, or put the value in the config
file, which is read per request. (`DaemonProcess.swift`, `RuntimeConfig.claudeExecutable`)

## Linux breaks in specific ways

`String` is not `CVarArg`, so `%@` formatting does not compile; `FoundationModels` (the `apple`
provider) must stay gated behind availability. The macOS build stays green while the Linux job
fails, so it is always found late. (commits `4456e41`, `227f643`, `da905cf`)

## CI runs Linux in a container on purpose

The Linux job uses the `swift:6.3.3-noble` image; only macOS uses `setup-swift@v3`, which on
Linux verifies its download against an empty keyring and fails intermittently. Simplifying the
matrix reintroduces a flaky job. (`.github/workflows/ci.yml`)

## Reproduce the Linux job locally

`mise run backend:test:linux` runs the tests in the same image with a separate scratch path, so
it does not fight the local `.build`. Needs Docker or Colima.

## Ports and stale servers

`scripts/dev.sh` frees ports held by a stale `dashboard` or `node` and refuses to start when a
foreign process holds one. `mise run doctor` reports toolchain, builds and port holders;
`mise run stop` kills leftovers. "The server will not start" is almost always a held port.
Forensics: [`DEBUG.md`](DEBUG.md).

## In development the dashboard home is inside the repo

`mise.toml` points `MVP_DASHBOARD_HOME` at `.local/dashboard-home`, so the registry, settings,
config and credentials used in development are not the ones in `~/.config/mvp-dashboard`. Data
"disappearing" between a mise task and a bare `swift run` is this.

## The change-event names in `README.md` are stale

The kinds are `projectsChanged`, `workspaceChanged(projectId:)`, `settingsChanged`,
`aiConfigChanged`. The README still says `board_changed`, which is nothing.
(`ChangeEvents.swift`)

## Secrets moved out of the config file

Pasted keys and OAuth credentials live in `credentials.json` (`0600`) next to `config.yaml`; a
legacy `api_key:` is migrated out on the next save. Order: environment, then `credentials.json`,
then the legacy field. Code reading a key from the config store finds nothing for a signed-in
provider. (`website/docs/server/configuration.md`)

## Vendor kinds are registered by their module, not by `standard()`

`AIProviderRegistry.standard()` must not register `.huggingface` or `.openrouter`;
`DashboardProviderHuggingFace` and `DashboardProviderOpenRouter` do, together with their
sign-in. `ProvidersTests.swift:174` asserts the set difference, so adding a vendor to
`standard()` fails a test that names no vendor. (dropped commit `f2320df`, tag
`superseded/huggingface-f2320df`)

## `provider_ids` is maintained by hand

swift-configuration cannot enumerate keys, so `ai.provider_ids` lists what exists. A provider
under `ai.providers` but missing there is invisible, with no error.

## The event socket drops on every backend rebuild

The server process owns the socket and the dev proxy adds its own resets; there is no
heartbeat, no sequence number, no replay yet. A stale board in development is expected today —
do not debug it as a new bug. (`conceptions/20260921-live-connection.md`)

## Four names for one product

`MVP Dashboard` (docs), `kanban-harness` (repository), `dashboard` (binary),
`mvp-dashboard-backend` (package), `mvp-dashboard-workspace` (pnpm); env vars and the config
directory use `mvp-dashboard`. Renaming the wrong one breaks everyone's config directory.

## Three minimum macOS versions are quoted

README says 14+, `Package.swift` declares 15, CI runs `macos-26`, the `apple` provider needs 26. The manifest is what decides whether the build succeeds.

## Prettier formats this folder too

`pnpm format:check` covers the repository, `docs/` included, and CI runs it in the web job — so
hand-written Markdown fails a job that has nothing to do with Markdown.

## The documentation exists three times, on purpose

`docs/` is agent-facing for the backend, `web/docs/` the same for the front end, `website/docs/`
is the published site. Fixing a fact in one place leaves the others lying, and
`mise run docs:build` fails on a broken link.

## `ponytail:` comments mark deliberate shortcuts

Such a comment records a simplification chosen on purpose, with its ceiling and upgrade path.
It is a decision, not an oversight: replacing it needs its reason to have stopped applying.

## What counts as verified

`mise run check` is what CI runs. For backend-only work, `mise run backend:test` plus
`mise run backend:test:linux`. "It builds" is not the bar; Linux is where this package fails.
