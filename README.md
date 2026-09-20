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

### Production-style (one process)

```sh
mise run serve        # builds the web app and a release binary, then serves both on :5175
```

Equivalent by hand: `pnpm build && backend/.build/release/dashboard serve --static-dir dist`.

### Reaching it from another machine

Everything binds to loopback by default (the API has no authentication). To use the dashboard from another device on your network:

```sh
mise run dev:lan      # dev: Vite on 0.0.0.0:5173, backend stays on loopback behind the proxy
mise run serve:lan    # prod-style: one process on 0.0.0.0:5175
```

Then open `http://<this machine's IP>:5173` (or `:5175`). If it still doesn't answer, the OS firewall is blocking the port — on macOS allow `node` / `dashboard` under _System Settings → Network → Firewall_, on Linux open the port in `ufw`/`firewalld`. Setting `MVP_DASHBOARD_HOST=0.0.0.0` in `.env.local` makes the plain `serve` / `backend:serve` tasks bind to all interfaces permanently.

### Environment

Set in `mise.toml` (override in a git-ignored `.env.local`):

| Variable             | Default                 | Meaning                                                                                                                                   |
| -------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `MVP_DASHBOARD_HOME` | `.local/dashboard-home` | Where the server/CLI keep `projects.sqlite` (registry) and `settings.json`. Outside mise it defaults to `$XDG_CONFIG_HOME/mvp-dashboard`. |
| `MVP_DASHBOARD_PORT` | `5175`                  | Port used by the `dev`, `serve` and `backend:serve` tasks.                                                                                |
| `MVP_DASHBOARD_HOST` | `127.0.0.1`             | Interface the servers bind to; `0.0.0.0` exposes them on the network (see "Reaching it from another machine").                            |

## Use

### Web

1. **Add a project** — sidebar → `+` → folder path (created if missing), optional name, storage (JSON or SQLite; the default comes from server settings). The folder is seeded with one board (TODO / Doing / Complete).
2. **Boards** — tabs at the top of the project page: `+ New board`, Rename, Duplicate, ← → reorder, Delete (with confirmation).
3. **Columns** — `+ Add column`; each column header has ✎ (name, WIP limit, default status), ← → and × (a board keeps at least one column).
4. **Cards** — `+ Add card` opens the card dialog; click a card to edit title, description, priority, status, column, due date, points, move it to another board, or delete it. ← → on a card moves it one column.
5. **Project page header** — switch the project's storage (JSON ⇄ SQLite, converted in place, old file kept) or **Unregister** it (files on disk are never deleted).
6. **Settings** — _This browser_: the API server URL this browser talks to (stored in `localStorage`; empty = same origin, with a Test connection button). _Server_: `settings.json` on the server — default storage for new projects and allowed browser origins (CORS) — applied live, no restart.

### CLI

`mise run cli -- <args>` during development, or `backend/.build/release/dashboard` after `mise run backend:release`. All output is JSON; errors go to stderr as `{"error": {"message": …}}` with exit code 1.

```sh
dashboard project add ~/work/demo [--name Demo] [--storage json|sqlite]
dashboard project list
dashboard project show   <name|id>
dashboard project boards <name|id>
dashboard project storage <name|id> json|sqlite     # convert in place, old file kept
dashboard project remove <name|id>                  # unregister only

dashboard settings show
dashboard settings set [--default-storage sqlite] [--cors-origin URL ...] [--clear-cors]

dashboard serve [--hostname 127.0.0.1] [--port 5175] [--static-dir dist] [--cors-origin URL ...]
dashboard --home <dir> …                            # registry/settings location (or MVP_DASHBOARD_HOME)
```

### HTTP API

Base path `/api`; JSON in and out; errors are `{"code": "NOT_FOUND" | "ALREADY_EXISTS" | "VALIDATION_FAILED" | "INTERNAL", "message": …}`.

| Method  | Path                                                   | Purpose                                                 |
| ------- | ------------------------------------------------------ | ------------------------------------------------------- |
| `GET`   | `/health`                                              | Liveness                                                |
| `GET`   | `/settings` · `PATCH /settings`                        | Server settings (`default_storage`, `cors_origins`)     |
| `GET`   | `/projects` · `POST /projects`                         | List / register (`{name, path, storage?}`)              |
| `GET`   | `/projects/{id}` · `PATCH` (`{storage}`) · `DELETE`    | Show / switch storage / unregister                      |
| `GET`   | `/projects/{id}/kanban/v1/boards` · `POST`             | Boards (`{name, card_prefix?, with_default_columns?}`)  |
| `PATCH` | `/projects/{id}/kanban/v1/boards/{b}` · `DELETE`       | Rename / reorder (`position`) / delete                  |
| `POST`  | `/projects/{id}/kanban/v1/boards/{b}/clone`            | Deep copy (`{name?}`)                                   |
| `GET`   | `/projects/{id}/kanban/v1/boards/{b}/columns` · `POST` | Columns (`{name, wip_limit?, default_status?}`)         |
| `PATCH` | `…/boards/{b}/columns/{c}` · `DELETE`                  | Edit / reorder / delete                                 |
| `GET`   | `/projects/{id}/kanban/v1/boards/{b}/cards`            | Cards of a board                                        |
| `POST`  | `/projects/{id}/kanban/v1/columns/{c}/cards`           | Create (`{title, description?, priority?}`)             |
| `PATCH` | `…/boards/{b}/cards/{card}` · `DELETE`                 | Edit; `column_id` moves, `board_id` moves across boards |

Shapes follow kanban-api's wire format (snake_case, explicit nulls, paginated lists as `{items, total, page, page_size, total_pages}`).

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
| `mise run clean`                                                                | Remove `dist/`, `coverage/`, `backend/.build/`         |

## Architecture

Dependencies point inward everywhere: interface → service → persistence → domain.

| Path                                         | Role                                                                                                                                                      |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/design-system/`                         | Reusable components over purple3 (`Button`, `Card`, `Modal`, …). The only layer that knows `hk-*` classes.                                                |
| `src/core/plugin/`                           | `DashboardPlugin` contract (`nav`, `routes`, optional `sidebar`) + registry.                                                                              |
| `src/core/shell/`, `src/core/settings/`      | App chrome and the browser-side settings slice (server URL, persisted to `localStorage`).                                                                 |
| `src/app/`                                   | Composition root: store, RTK Query `baseApi` (base URL resolved per request), router, plugin list.                                                        |
| `src/plugins/projects/`                      | Sidebar project list, project page, board tabs, columns, card/column/board dialogs.                                                                       |
| `src/plugins/settings/`                      | Settings page: browser card + server card.                                                                                                                |
| `backend/Sources/DashboardDomain`            | `Project`, `ProjectRegistry`, `Settings`, and the kanban `Workspace` aggregate (numbering, WIP, status rules). Pure.                                      |
| `backend/Sources/DashboardPersistence`       | `ProjectStore` / `WorkspaceStore` / `SettingsStore` protocols, in-memory stores, shared contract tests, RFC 3339 codec.                                   |
| `backend/Sources/DashboardPersistenceJSON`   | `KanbanJSONStore` (kanban-rs v18 envelope), JSON registry and settings stores; atomic writes.                                                             |
| `backend/Sources/DashboardPersistenceFluent` | Fluent SQLite stores for the registry and workspaces; `SQLiteDatabasePool`.                                                                               |
| `backend/Sources/DashboardService`           | `ProjectService`, `SettingsService` actors; clock/ids via cascade-kit `@Dependency`.                                                                      |
| `backend/Sources/DashboardAPI`               | Wire DTOs (kanban-api shapes, `Page`, `ApiError`).                                                                                                        |
| `backend/Sources/DashboardServer`            | Vapor app: routes, error envelope, live CORS, services in a cascade-kit container; `WorkspaceStores.factory` is the single `StorageKind` → store mapping. |
| `backend/Sources/DashboardCLI`               | `dashboard` executable.                                                                                                                                   |

JSON and SQLite are interchangeable by construction: both stores implement the same protocol against the same `Workspace`, pass the same contract test, and an interchange test proves JSON → SQLite → JSON is lossless.

## Adding a web plugin

1. Create `src/plugins/<name>/index.tsx` exporting a `DashboardPlugin` (`id`, `name`, `nav`, `routes`, optional `sidebar`).
2. Server data: `baseApi.injectEndpoints(...)`. Local state: `createSlice(...).injectInto(rootReducer)` and augment `LazyLoadedSlices`.
3. Add it to the list in `src/app/plugins.ts`.

## CI

`.github/workflows/ci.yml` runs the web checks (audit, Prettier, ESLint, tsc, tests with coverage, build) and the Swift package tests on macOS and Linux.
