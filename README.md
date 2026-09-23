# MVP Dashboard

A plugin-based project dashboard: a React 19 + TypeScript + Redux Toolkit web app (styled with Heroku's [purple3](https://design.herokai.com/purple3/)) backed by a Swift 6 server (Vapor 4 + Fluent) and a CLI (swift-argument-parser), wired with [cascade-kit](https://github.com/amine2233/cascade-kit).

Each **project** is a folder on your machine holding one kanban workspace — boards, columns, cards — stored either as `kanban.json` ([kanban-rs](https://github.com/kanban-rs/kanban) v18 format, so the `kanban` CLI/TUI opens it too) or as `kanban.sqlite` (Fluent). Both formats hold the same aggregate; a project can switch between them at any time without losing data.

## Prerequisites

- [mise](https://mise.jdx.dev) — installs the pinned toolchain (`mise.toml`: Node 24, pnpm 12, Swift 6.3) and provides the tasks below.
- macOS 14+ or Linux with a Swift 6 toolchain.

```sh
mise install          # toolchain
mise run setup        # pnpm install + swift package resolve
```

Without mise: install Node ≥ 22, pnpm 12 and Swift ≥ 6.1 yourself and run the `pnpm` / `swift` commands the tasks wrap (see `mise.toml`).

## Run

### Development (two dev servers)

```sh
mise run dev
```

Starts the API on `http://127.0.0.1:5175` and Vite on `http://localhost:5173` (Vite proxies `/api` to the backend, so no CORS setup is needed). Ctrl-C stops both. Or run them separately: `mise run backend:serve` and `mise run web:dev`.

If it won't start: `mise run doctor` reports toolchain, build outputs and who holds the ports; `mise run stop` kills servers left behind by a closed terminal. `dev` already stops stale copies of its own servers and refuses to start when a foreign process holds a port (change `MVP_DASHBOARD_PORT` / `MVP_DASHBOARD_WEB_PORT` in `.env.local` in that case).

### Production-style (one process)

```sh
mise run serve        # builds the web app and a release binary, then serves both on :5175
```

Equivalent by hand: `pnpm build && ./.build/release/dashboard serve --static-dir web/dist`.

### Reaching it from another machine

Everything binds to loopback by default (the API has no authentication). To use the dashboard from another device on your network:

```sh
mise run dev:lan      # dev: Vite on 0.0.0.0:5173, backend stays on loopback behind the proxy
mise run serve:lan    # prod-style: one process on 0.0.0.0:5175
```

Then open `http://<this machine's IP>:5173` (or `:5175`). If it still doesn't answer, the OS firewall is blocking the port — on macOS allow `node` / `dashboard` under _System Settings → Network → Firewall_, on Linux open the port in `ufw`/`firewalld`. Setting `MVP_DASHBOARD_HOST=0.0.0.0` in `.env.local` makes the plain `serve` / `backend:serve` tasks bind to all interfaces permanently.

### Environment

Set in `mise.toml` (override in a git-ignored `.env.local`):

| Variable                                  | Default                 | Meaning                                                                                                                                   |
| ----------------------------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `MVP_DASHBOARD_HOME`                      | `.local/dashboard-home` | Where the server/CLI keep `projects.sqlite` (registry) and `settings.json`. Outside mise it defaults to `$XDG_CONFIG_HOME/mvp-dashboard`. |
| `MVP_DASHBOARD_PORT`                      | `5175`                  | Port used by the `dev`, `serve` and `backend:serve` tasks.                                                                                |
| `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` | —                       | Supplies a provider's API key from the environment instead of the config file (never written back).                                       |
| `MVP_DASHBOARD_HOST`                      | `127.0.0.1`             | Interface the servers bind to; `0.0.0.0` exposes them on the network (see "Reaching it from another machine").                            |

## Use

### Web

1. **Add a project** — sidebar → `+` → folder path (created if missing), optional name, storage (JSON or SQLite; the default comes from server settings). The folder is seeded with one board (TODO / Doing / Complete).
2. **Boards** — tabs at the top of the project page: `+ New board`, Rename, Duplicate, ← → reorder, Delete (with confirmation).
3. **Columns** — `+ Add column`; each column header has ✎ (name, WIP limit, default status), ← → and × (a board keeps at least one column).
4. **Cards** — `+ Add card` opens the card dialog; click a card to edit title, description, priority, status, column, due date, points, move it to another board, or delete it. ← → on a card moves it one column.
5. **Project page header** — switch the project's storage (JSON ⇄ SQLite, converted in place, old file kept) or **Unregister** it (files on disk are never deleted).
6. **Settings** — _This browser_: the API server URL this browser talks to (stored in `localStorage`; empty = same origin, with a Test connection button). _Server_: `settings.json` on the server — default storage for new projects and allowed browser origins (CORS) — applied live, no restart. _AI providers_: `config.json`/`config.yaml` on the server, see below.
7. **Draft with AI** — in the new-card dialog, describe the ticket in a sentence; the title and description fill in as the model types. The activity panel shows the steps (Prepare · Wait for model · Streaming · Validate), provider, time to first token, tokens and cost, which fields have arrived, and under _Details_ the per-phase durations, error codes, a _Copy log_ button and the raw model output. Nothing is created until you press Create.
8. **Sub-tasks** — a draft splits a big idea into sub-tasks (only when it clearly needs several independent pieces); they appear as ticked, editable rows and _Create 1 + N cards_ creates the tree in one request. On the board a parent shows its sub-tasks nested inside it with the column each one is in (`⌥ 1/3` done); drag a sub-task or use its arrows to move it — it stays under its parent, like Jira. The card dialog links a sub-task to its parent and lists a parent's sub-tasks. Links are kanban-rs `graph.spawns` edges, so the file keeps working there.
9. **Cost** — a card created from a draft remembers what it cost (`✨ $0.03` on the board, details in the card dialog). Claude Code reports its real cost; other vendors are priced from the provider's pricing (marked ≈), local models are free. This is the first entry of a card's cost history; backlog→done tracking and project totals come next.

### AI providers

Providers live in `config.json` (or `config.yaml`) under the dashboard home; the web settings, the CLI and a hand edit all land in the same file, applied live. Kinds:

| Kind          | Backed by                                                                               | Needs             |
| ------------- | --------------------------------------------------------------------------------------- | ----------------- |
| `claude_code` | Claude Code CLI in headless mode (`claude -p`), streaming partial messages              | `claude` login    |
| `apple`       | Apple's on-device model (`SystemLanguageModel`)                                         | macOS 26          |
| `anthropic`   | Anthropic Messages API                                                                  | API key           |
| `openai`      | Any OpenAI-compatible `/v1` endpoint (OpenAI, Mistral, Groq, LM Studio…) via `base_url` | API key (or none) |
| `gemini`      | Google Gemini                                                                           | API key           |
| `ollama`      | Local Ollama (`http://127.0.0.1:11434` by default)                                      | Ollama running    |

Each provider can carry `pricing: {input_per_million, output_per_million}` (USD) so drafts get a cost even when the vendor reports none. Everything but `claude_code` goes through [AnyLanguageModel](https://github.com/mattt/AnyLanguageModel), so adding a vendor is one line in `AIProviderRegistry.standard`. Keys are write-only (the API only reports `has_api_key`), the file is written `0600`, and `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` keeps a key out of the file entirely. Card text is passed to the model as data, never as instructions.

### CLI

`mise run cli -- <args>` during development, or `./.build/release/dashboard` after `mise run backend:release`. All output is JSON; errors go to stderr as `{"error": {"message": …}}` with exit code 1.

**Where commands go.** Every command routes through this home's daemon, started on the first command that finds nothing answering. The daemon is the single writer, so a change made from the CLI or MCP reaches an open browser without a refresh, and nothing can work on the files behind a running owner's back. There is no flag to point a command elsewhere — the home comes from `$MVP_DASHBOARD_HOME`, else a `./.kanban-harness/` where you ran, else `~/.config/kanban-harness`.

```sh
dashboard project add ~/work/demo [--name Demo] [--storage json|sqlite]
dashboard project list
dashboard project show   <name|id>
dashboard project boards <name|id>
dashboard project storage <name|id> json|sqlite     # convert in place, old file kept
dashboard project remove <name|id>                  # unregister only

dashboard settings show
dashboard settings set [--default-storage sqlite] [--cors-origin URL ...] [--clear-cors]

dashboard ai providers list | add <id> --kind K --model M [--base-url URL] [--api-key KEY] [--input-price N --output-price N] | remove <id> | default <id>
dashboard ai ticket <project> "idea" [--board B] [--provider P] [--stream] [--create [--column C]]   # draft (and create) a card; --stream narrates on stderr
dashboard mcp                                       # MCP server over stdio (boards & cards as tools)
dashboard serve [--hostname 127.0.0.1] [--port 5175] [--static-dir dist] [--cors-origin URL ...]
dashboard daemon start | stop | status              # the process that owns this home's data
```

### HTTP API

Base path `/api`; JSON in and out; errors are `{"code": "NOT_FOUND" | "ALREADY_EXISTS" | "VALIDATION_FAILED" | "INTERNAL", "message": …}`.

| Method  | Path                                                                                       | Purpose                                                                                                                            |
| ------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `GET`   | `/health`                                                                                  | Liveness                                                                                                                           |
| `GET`   | `/settings` · `PATCH /settings`                                                            | Server settings (`default_storage`, `cors_origins`)                                                                                |
| `GET`   | `/projects` · `POST /projects`                                                             | List / register (`{name, path, storage?}`)                                                                                         |
| `GET`   | `/projects/{id}` · `PATCH` (`{storage}`) · `DELETE`                                        | Show / switch storage / unregister                                                                                                 |
| `GET`   | `/projects/{id}/kanban/v1/boards` · `POST`                                                 | Boards (`{name, card_prefix?, with_default_columns?}`)                                                                             |
| `PATCH` | `/projects/{id}/kanban/v1/boards/{b}` · `DELETE`                                           | Rename / reorder (`position`) / delete                                                                                             |
| `POST`  | `/projects/{id}/kanban/v1/boards/{b}/clone`                                                | Deep copy (`{name?}`)                                                                                                              |
| `GET`   | `/projects/{id}/kanban/v1/boards/{b}/columns` · `POST`                                     | Columns (`{name, wip_limit?, default_status?}`)                                                                                    |
| `PATCH` | `…/boards/{b}/columns/{c}` · `DELETE`                                                      | Edit / reorder / delete                                                                                                            |
| `GET`   | `/projects/{id}/kanban/v1/boards/{b}/cards`                                                | Cards of a board                                                                                                                   |
| `POST`  | `/projects/{id}/kanban/v1/columns/{c}/cards`                                               | Create (`{title, description?, priority?, ai_cost?, subtasks?}`); sub-tasks are created and linked atomically                      |
| `GET`   | `…/boards/{b}/cards/{card}/children` · `PUT …/parent`                                      | A card's sub-tasks · link (`{parent_id}`) or detach (`null`); cards carry `parent_id` and `children: {total, done}`                |
| `PATCH` | `…/boards/{b}/cards/{card}` · `DELETE`                                                     | Edit; `column_id` moves, `board_id` moves across boards                                                                            |
| `GET`   | `/settings/ai` · `PUT /settings/ai/providers/{id}` · `DELETE` · `PUT /settings/ai/default` | AI providers (keys write-only)                                                                                                     |
| `POST`  | `/projects/{id}/ai/tickets/draft`                                                          | `{idea, board_id, provider?}` → draft; with `Accept: text/event-stream`, frames `stage` / `partial` / `usage` / `result` / `error` |
| `GET`   | `/events` (WebSocket)                                                                      | Change events (`projects_changed`, `board_changed`, …)                                                                             |

Shapes follow kanban-api's wire format (snake_case, explicit nulls, paginated lists as `{items, total, page, page_size, total_pages}`).

### MCP (AI agents on your boards)

The same boards and cards are exposed as [MCP](https://modelcontextprotocol.io) tools — `list_projects`, `list_boards`, `create_board`, `list_columns`, `list_cards`, `create_card`, `create_subtasks`, `list_card_children`, `set_card_parent`, `remove_card_parent`, `update_card`, `move_card`, `delete_card` — built on the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk). Two transports, same tools:

- **stdio** — `dashboard mcp`. When a dashboard server is running the tools go through it (single writer, browsers update live); otherwise they work on the files.
- **HTTP** — `POST http://127.0.0.1:5175/mcp` on the running server (streamable HTTP, localhost origins only).

Claude Code, for example:

```sh
claude mcp add dashboard -- dashboard mcp                       # stdio
claude mcp add --transport http dashboard http://127.0.0.1:5175/mcp
```

then "in project Demo, move task-12 to In progress" just works, with your Claude subscription — no API key involved.

## Tasks

| Task                                                                            | What it does                                           |
| ------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `mise run setup`                                                                | `pnpm install` + `swift package resolve`               |
| `mise run dev`                                                                  | Backend + web dev servers                              |
| `mise run dev:lan` / `serve:lan`                                                | Same, reachable from other machines on the network     |
| `mise run serve`                                                                | Release binary serving the built web app               |
| `mise run test`                                                                 | Web (Vitest) + backend (Swift Testing) tests           |
| `mise run check`                                                                | Prettier, ESLint, tsc, tests and builds — what CI runs |
| `mise run web:dev` / `web:test` / `web:check` / `web:build`                     | Web-only tasks                                         |
| `mise run backend:build` / `backend:test` / `backend:serve` / `backend:release` | Backend-only tasks                                     |
| `mise run cli -- …`                                                             | Run the dashboard CLI from source                      |
| `mise run clean`                                                                | Remove `web/dist/`, `web/coverage/`, `.build/`         |

## Architecture

The repository is one Swift package at the root (`Package.swift`, `Sources/`, `Tests/`) plus a pnpm
workspace for the web side (`web/` app, `web/packages/*` libraries, `website/` docs). Dependencies
point inward everywhere: interface → service → persistence → domain.

| Path                                        | Role                                                                                                                                                                                                |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `web/packages/design-system/`               | `@mvp/design-system`: reusable components over purple3 (`Button`, `Card`, `Modal`, `Markdown`, …). The only layer that knows `hk-*` classes; no state.                                              |
| `web/packages/kanban-model/`                | `@mvp/kanban-model`: wire types and pure functions over the board (grouping, hierarchy index, colours, checklists, AI draft helpers). No React, no Redux.                                           |
| `web/packages/state/`                       | `@mvp/state`: the Redux store — RTK Query endpoints, browser settings, the live socket, the AI stream. No components. `@mvp/state/testing` stubs the server for tests.                              |
| `web/src/core/plugin/`                      | `DashboardPlugin` contract (`nav`, `routes`, optional `sidebar`) + registry.                                                                                                                        |
| `web/src/core/shell/`, `src/core/settings/` | App chrome; theme hook and picker.                                                                                                                                                                  |
| `web/src/app/`                              | Composition root: router, store provider, plugin list. See [Web architecture](website/docs/web/architecture.md).                                                                                    |
| `web/src/plugins/projects/`                 | Sidebar project list, project page; `board/` (columns, cards, drag and drop), `card/` (dialog over a pure form reducer), `assistant/` (Draft with AI + activity panel).                             |
| `web/src/plugins/settings/`                 | Settings page: browser card + server card.                                                                                                                                                          |
| `Sources/DashboardDomain`                   | `Project`, `ProjectRegistry`, `Settings`, and the kanban `Workspace` aggregate (numbering, WIP, status rules). Pure.                                                                                |
| `Sources/DashboardPersistence`              | `ProjectStore` / `WorkspaceStore` / `SettingsStore` protocols, in-memory stores, shared contract tests, RFC 3339 codec.                                                                             |
| `Sources/DashboardPersistenceJSON`          | `KanbanJSONStore` (kanban-rs v18 envelope), JSON registry and settings stores; atomic writes.                                                                                                       |
| `Sources/DashboardPersistenceConfig`        | `config.json`/`config.yaml` AI provider store: swift-configuration reads (file + env), atomic private writes.                                                                                       |
| `Sources/DashboardPersistenceFluent`        | Fluent SQLite stores for the registry and workspaces; `SQLiteDatabasePool`.                                                                                                                         |
| `Sources/DashboardService`                  | `ProjectService`, `SettingsService` actors; clock/ids via cascade-kit `@Dependency`.                                                                                                                |
| `Sources/DashboardAI`                       | `AIProvider` streaming contract, `AssistantService` (board context → prompt → partial drafts → validated `TicketDraft`), `JSONCompleter` for half-typed JSON.                                       |
| `Sources/DashboardAIProviders`              | `AnyLanguageModelProvider` (apple/anthropic/openai/gemini/ollama) and `ClaudeCodeProvider` (headless `claude -p`, stream-json).                                                                     |
| `Sources/DashboardOAuth`                    | Browser sign-in, vendor-agnostic: PKCE, `ProviderSignIn` contract, `OAuthCodeFlow` (authorization code + refresh), one-shot `SignInSessions`, stubbable `HTTPTransport`.                            |
| `Sources/DashboardProviderHuggingFace`      | Hugging Face Inference Providers: provider factory over the OpenAI-compatible router + OAuth sign-in (`OAuthCodeFlow` with the registered app).                                                     |
| `Sources/DashboardProviderOpenRouter`       | OpenRouter: provider factory + `OpenRouterSignIn` (PKCE exchange that returns an API key). One module per vendor: add another the same way.                                                         |
| `Sources/DashboardAPI`                      | Wire DTOs (kanban-api shapes, `Page`, `ApiError`, `AssistantFrame` + `SSEParser`).                                                                                                                  |
| `Sources/DashboardClient`                   | HTTP implementations of the command protocols (what the CLI uses when a server is running), including the event-stream client.                                                                      |
| `Sources/DashboardMCP`                      | MCP tool catalogue and dispatcher over the same command protocols.                                                                                                                                  |
| `Sources/DashboardRuntime`                  | Composition root shared by CLI and server: cascade-kit `ServiceKey`s, `DashboardRuntime.register/shutdown`, `RuntimeConfig`; `WorkspaceStores.factory` is the single `StorageKind` → store mapping. |
| `Sources/DashboardServer`                   | Vapor app: routes, error envelope (+ `X-Request-Id`), live CORS, app and per-request cascade-kit containers.                                                                                        |
| `Sources/DashboardCLI`                      | `dashboard` executable; one runtime container per invocation, `--verbose` bound through `\.logger`.                                                                                                 |

### Source of truth

- **Server** — owns the files/SQLite and is the single writer; it publishes a change event for every mutation (`/api/events`).
- **CLI** — a client of the server when one runs (same API, same DTOs); local file mode only as a fallback.
- **Web** — Redux is the frontend's source of truth: RTK Query caches mirror the server and the event socket keeps them fresh; components read the store, never the network.

### Dependency injection (cascade-kit)

Two mechanisms, used for two different things:

- **Container** (`CascadeKit.Application` / `Request`) for services with lifetimes. `DashboardRuntime.register` wires stores, the SQLite pool and the services once; `DashboardRuntime.shutdown` tears them down in reverse. The CLI builds one container per invocation; the server keeps one on the Vapor app and layers a `CascadeKit.Request` container per request (request id → `X-Request-Id`), falling through to the app container for everything else.
- **`@Dependency`** for ambient values: `\.now`, `\.uuid`, `\.home` (data directory, from `MVP_DASHBOARD_HOME`/XDG), `\.logger`. Production reads `liveValue`; tests pin them with `withTestDependencies { $0.now = … }`; the CLI binds `\.logger.logLevel` from `--verbose`.

JSON and SQLite are interchangeable by construction: both stores implement the same protocol against the same `Workspace`, pass the same contract test, and an interchange test proves JSON → SQLite → JSON is lossless.

## Adding a web plugin

1. Create `web/src/plugins/<name>/index.tsx` exporting a `DashboardPlugin` (`id`, `name`, `nav`, `routes`, optional `sidebar`).
2. Server data and local state live in `web/packages/state` (`api/<resource>.ts` with `baseApi.injectEndpoints`, or a slice added to `reducer.ts`), exported from its `index.ts`.
3. Add it to the list in `web/src/app/plugins.ts`.

## CI

`.github/workflows/ci.yml` runs the web checks (audit, Prettier, ESLint, tsc, tests with coverage, build) and the Swift package tests on macOS and Linux.
