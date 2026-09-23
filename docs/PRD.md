# Product Requirements — kanban-harness

## TL;DR

A personal kanban dashboard where an AI drafts the tickets and you keep the board. Projects
are folders on your machine; one Swift server owns them; three surfaces drive it — web app,
CLI, MCP server. Single user, single machine, no cloud.

## Problem

A usable card is a title, a description, acceptance criteria, a priority, an estimate and
often a split into sub-tasks. Writing that by hand is slow enough to be skipped, and skipping
it is what makes a backlog unreadable.

The alternatives each miss one thing: hosted trackers (Jira, Linear) draft well but own your
data; `kanban-rs` keeps the data local but has no drafting and no browser; an LLM chat window
produces text that nothing links to a board.

This product keeps the file-based side — a project is a folder, `kanban.json` stays
`kanban-rs` v18 — and adds drafting, a browser, live updates and agent access on top.

## Users

**Human.** A developer on their own machine. The only account: no authentication, loopback by
default. Registers folders, drafts tickets and reviews them before they exist, moves cards
from whichever surface is open, checks what drafting cost.

**AI agent.** A coding agent (Claude Code, Cursor, any MCP client) on the same machine, acting
on the board through MCP tools, routed through the server so browsers stay live.

> TODO(owner): are drafting agents (`docs/conceptions/20260920-ai-agents.md`) a third user class or a
> configuration of the second?

## Goals

1. A project is a folder you own; `kanban.json` stays valid `kanban-rs` v18.
2. JSON and SQLite hold the same aggregate and switch in place without loss.
3. One sentence produces a complete draft card — title, description, criteria, priority,
   points, sub-tasks when needed — reviewed before anything is written.
4. Web, CLI and MCP drive the same server and the same data; the server is the single writer.
5. A change on any surface reaches every open browser without a reload.
6. Every AI-drafted card records its provider and its cost.
7. Providers are pluggable, including free ones, so the product works with no API key.
8. Card text reaches the model as data, never as instructions.
9. Keys are write-only over the API; an environment-supplied key is never written to disk.
10. Everything works offline against local models and local files.
11. macOS and Linux, both verified by CI.

## Non-goals

1. Multi-user, accounts, authentication, authorization.
2. A hosted deployment. One process, one machine, loopback unless opted out.
3. Multi-server or a shared event log across processes.
4. Client-to-server commands over the event socket; HTTP is the command channel.
5. Replacing the `kanban-rs` CLI/TUI — format compatibility, not feature parity.
6. Agents creating or moving cards without a human when drafting.
7. Hosting or proxying model inference.
8. Native mobile or desktop clients.

> TODO(owner): 5 and 8 are inferred from the absence of such work, not stated anywhere.

## Product surface

Structure is in [`ARCHITECTURE.md`](ARCHITECTURE.md); this is scope only.

- **Server** — owns the data, single writer, single source of change events. No notion of
  users; writes nothing outside the project folder and the dashboard home.
- **CLI** — everything the browser can do, plus a file-only fallback when no server runs.
  Machine-readable output. Never a second concurrent writer.
- **Web app** — where a human looks at a board and watches a draft being written. Holds no
  state the server does not have, apart from per-browser preferences.
- **MCP server** — boards and cards as tools for AI agents. Same operations as the other
  surfaces, none privileged; read-only for drafting agents.
- **Docs site** — the published reference and the design notes.

## Data contract

- A project is a folder. Registering records a path; unregistering forgets it and deletes
  nothing.
- One workspace per project: `kanban.json` or `kanban.sqlite`, same aggregate.
- `kanban.json` is `kanban-rs` v18 and must stay openable by its CLI/TUI; sub-task links are
  `graph.spawns` edges.
- JSON → SQLite → JSON is lossless; a project switches format at any time and the previous
  file is kept.
- Hand edits win: files are read on every request, no restart.
- The dashboard home (`MVP_DASHBOARD_HOME`, else XDG) holds the registry, `settings.json`,
  `config.yaml` and `credentials.json` — never project data.
- Wire shapes follow kanban-api: snake_case, explicit nulls, `{items, total, page, page_size,
total_pages}`.

**Never break:** a written `kanban.json` opens in `kanban-rs`; a conversion loses nothing;
unregistering leaves the folder intact; an env-supplied key never lands on disk.

## Functional requirements

Sourced from `README.md` unless the row says otherwise. `SHOULD` and `MAY` rows are the
backlog in each note's `## Tasks` section.

| ID     | Requirement                                                                                 | Priority |
| ------ | ------------------------------------------------------------------------------------------- | -------- |
| SRV-01 | Register, list, show, unregister projects; unregistering deletes no file                    | MUST     |
| SRV-02 | Seed a new project with one board (TODO / Doing / Complete)                                 | MUST     |
| SRV-03 | Create, rename, reorder, duplicate, delete boards                                           | MUST     |
| SRV-04 | Columns with WIP limit and default status; reorder, delete; a board keeps one               | MUST     |
| SRV-05 | Create, edit, move, delete cards, including across boards                                   | MUST     |
| SRV-06 | Create a card with its sub-tasks atomically; link/detach a parent; report `children`        | MUST     |
| SRV-07 | Convert a project between JSON and SQLite in place, keeping the previous file               | MUST     |
| SRV-08 | Server settings (`default_storage`, `cors_origins`) applied live, no restart                | MUST     |
| SRV-09 | AI providers with write-only keys, `0600` credentials, env keys never written back          | MUST     |
| SRV-10 | Draft a ticket and stream `stage` / `partial` / `usage` / `result` / `error`                | MUST     |
| SRV-11 | Publish a change event for every mutation on a subscribable stream                          | MUST     |
| SRV-12 | Errors as `{code, message}` with a stable code set and a request id header                  | MUST     |
| SRV-13 | Card and board text reaches a model as data, never as instructions                          | MUST     |
| SRV-14 | Loopback by default; LAN exposure only on explicit opt-in                                   | MUST     |
| SRV-15 | Serve the built web app from the same process                                               | MUST     |
| SRV-16 | Never trap on data it reads — corrupt files and provider failures become errors             | SHOULD   |
| SRV-17 | Heartbeat the event stream; answer a stale resume with a resync                             | SHOULD   |
| SRV-18 | Retain recent events so a short disconnection replays instead of refetching                 | SHOULD   |
| SRV-19 | Report liveness and process identity (pid, uptime, epoch, clients)                          | MAY      |
| SRV-20 | Resolve named drafting agents from markdown files, read on every draft                      | MAY      |
| CLI-01 | JSON on stdout; errors on stderr with exit code 1                                           | MUST     |
| CLI-02 | Use a running server when one answers, files otherwise; `--remote` / `--local` force either | MUST     |
| CLI-03 | Projects: add, list, show, boards, storage, remove                                          | MUST     |
| CLI-04 | Read and write server settings                                                              | MUST     |
| CLI-05 | AI providers: list, add, remove, default                                                    | MUST     |
| CLI-06 | Draft a ticket, optionally streaming and creating the card                                  | MUST     |
| CLI-07 | Run the MCP server over stdio                                                               | MUST     |
| CLI-08 | Run the HTTP server (host, port, static dir, CORS origins)                                  | MUST     |
| CLI-09 | Explicit dashboard home and a verbosity flag                                                | SHOULD   |
| CLI-10 | Select a drafting agent per invocation and manage the agent files                           | MAY      |
| WEB-01 | Add a project: path (created if missing), optional name, storage kind                       | MUST     |
| WEB-02 | Boards from tabs: create, rename, duplicate, reorder, delete with confirmation              | MUST     |
| WEB-03 | Columns inline: add, edit name / WIP / default status, reorder, delete                      | MUST     |
| WEB-04 | Card dialog: title, description, priority, status, column, due date, points, board, delete  | MUST     |
| WEB-05 | Move a card by drag and drop and by keyboard-reachable arrows                               | MUST     |
| WEB-06 | Sub-tasks nested under their parent with a done count; a dragged sub-task stays under it    | MUST     |
| WEB-07 | Draft with AI in the new-card dialog, filling fields as the model types                     | MUST     |
| WEB-08 | Activity panel: stages, provider, time to first token, tokens, cost, durations, raw output  | MUST     |
| WEB-09 | Nothing created until Create; sub-tasks created with the parent in one request              | MUST     |
| WEB-10 | Show what a drafted card cost, on the board and in the dialog                               | MUST     |
| WEB-11 | Switch a project's storage kind and unregister it                                           | MUST     |
| WEB-12 | Settings: browser API URL, server defaults and CORS, AI providers                           | MUST     |
| WEB-13 | Markdown descriptions with clickable checklists                                             | MUST     |
| WEB-14 | Refresh on a change from any surface, without a reload                                      | MUST     |
| WEB-15 | All server state through the store; components never call the network                       | MUST     |
| WEB-16 | New app areas registered as plugins (nav, routes, optional sidebar)                         | SHOULD   |
| WEB-17 | Reconnect on visible / online / successful request; distinguish reconnecting from stale     | SHOULD   |
| WEB-18 | Choose the drafting agent next to the provider; edit agents in settings                     | MAY      |
| MCP-01 | Projects, boards, columns, cards as tools, with sub-tasks and parent links                  | MUST     |
| MCP-02 | Same tools over stdio and streamable HTTP; HTTP restricted to local origins                 | MUST     |
| MCP-03 | Route through a running server so it stays the single writer                                | MUST     |
| MCP-04 | Expose agents and ticket drafting as tools                                                  | MAY      |
| MCP-05 | Let drafting agents call external MCP servers, board tools read-only and bounded            | MAY      |
| DOC-01 | Publish a static site: overview, getting started, architecture, each surface                | MUST     |
| DOC-02 | One design note per planned feature: built first, deferred, how the deferred part works     | MUST     |
| DOC-03 | Keep `README.md` accurate as the quick reference                                            | MUST     |

Sources for the non-`README.md` rows: SRV-16 to SRV-19 and WEB-17 from
`docs/conceptions/20260921-live-connection.md`; SRV-20, CLI-10, WEB-18, MCP-04 from
`docs/conceptions/20260920-ai-agents.md`; MCP-05 from `docs/conceptions/20260920-mcp-servers.md`; WEB-13 and
WEB-14 from `website/docs/index.md`; DOC-02 from `docs/conceptions/README.md`.

## Non-functional requirements

- **Portability.** macOS and Linux, both in CI. `Package.swift` declares macOS 15; `README.md`
  says 14+ (see Open questions).
- **Toolchain.** Pinned in `mise.toml`: Node 24, pnpm 12, Swift 6.3.
- **Durability.** Atomic writes everywhere; credentials `0600`; a conversion keeps the old
  file; no operation deletes a user file.
- **Security.** No authentication by design; loopback default; explicit CORS list; keys
  write-only; board text treated as data.
- **Offline.** Everything but a remote provider works with no network.
- **Gates.** `mise run check` is what CI runs; the store contract test and the JSON → SQLite →
  JSON test guard the data contract.
- **Live updates.** A disconnection must be survivable and the board correct after any gap.
  Not met today — target in `docs/conceptions/20260921-live-connection.md`.

> TODO(owner): no performance budget, no accessibility requirements, no licence or release
> policy exists in any source.

## Success criteria

1. Clean checkout to a working board in the browser with the documented commands only.
2. A project created here opens unchanged in the `kanban-rs` CLI/TUI.
3. JSON → SQLite → JSON produces the same workspace, proven by test.
4. A draft from one sentence needs no structural editing before Create.
5. Cancelling a draft writes nothing.
6. A card created from the CLI or by an agent appears in an open browser without a reload.
7. Every drafted card shows its provider and cost — exact for Claude Code, marked estimated
   for priced vendors.
8. A card can be drafted with no API key configured.
9. An env-supplied key is never found in a config file after any write.
10. `mise run check` passes on macOS and Linux.
11. After a laptop sleep, the browser shows a correct board within seconds.

> TODO(owner): decide which of these become automated checks.

## Open questions

Each one blocks a task or a theme; none has a design note, because none has been decided.

- Product name: `MVP Dashboard`, `kanban-harness`, `dashboard`, `mvp-dashboard-backend`. The
  rest become aliases. Blocks the macOS version reconciliation below.
- Minimum macOS: README 14+, package 15, `apple` provider 26.
- Drafting agents: distinct user class or configuration? Shapes
  [`conceptions/20260920-ai-agents.md`](conceptions/20260920-ai-agents.md).
- Performance budgets, or a statement that they are out of scope.
- Licence, distribution, versioning.
- Which of the success criteria above become automated checks.
- Are non-goals 5 and 8 real, or just unstarted?
- Performance budgets, accessibility, licence and versioning.
- Cost tracking beyond the first entry (backlog-to-done, project totals).
- Which conception notes are committed scope and which are speculative.

Sources: `README.md`, `website/docs/`, `docs/conceptions/`, `Package.swift`, `mise.toml`,
`Sources/`, `Tests/`, `git log`.
