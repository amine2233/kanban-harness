# MVP Dashboard

Plugin-based dashboard (React 19 + TypeScript + Redux Toolkit, styled with Heroku's [purple3](https://design.herokai.com/purple3/)) backed by a Swift server (Vapor 4 + Fluent) and CLI (swift-argument-parser), wired with [cascade-kit](https://github.com/amine2233/cascade-kit). Each project is a folder on your machine holding its board data as either `kanban.json` ([kanban-rs](https://github.com/kanban-rs/kanban) v18 format, so the `kanban` CLI/TUI can open it) or `kanban.sqlite` (Fluent). Both formats carry the same `Workspace` aggregate and a project can switch between them at any time.

## Run

```sh
# API + CLI (Swift 6)
cd backend && swift run dashboard serve                     # http://127.0.0.1:5175

# Web (proxies /api to the server above)
pnpm install && pnpm dev                                    # http://localhost:5173
```

Single binary deployment: `pnpm build && dashboard serve --static-dir dist`.

## CLI

```sh
dashboard project add ~/work/demo --name Demo [--storage json|sqlite]
dashboard project storage Demo sqlite        # convert in place, old file kept
dashboard project list | show <name|id> | remove <name|id> | boards <name|id>
dashboard serve [--hostname 127.0.0.1] [--port 5175] [--static-dir dist]
```

All output is JSON. The registry is a Fluent SQLite database at `$XDG_CONFIG_HOME/mvp-dashboard/projects.sqlite` (`--home` / `MVP_DASHBOARD_HOME` override). Removing a project never deletes files.

## Layout

| Path                                        | Role                                                                                        |
| ------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `src/design-system/`                        | Reusable components wrapping purple3 classes. The only layer that knows `hk-*` class names. |
| `src/core/plugin/`                          | `DashboardPlugin` contract (`nav`, `routes`, optional `sidebar` section) + registry.        |
| `src/core/shell/`                           | App chrome: top bar, sidebar, layout, `shell` slice.                                        |
| `src/app/`                                  | Composition root: store, RTK Query `baseApi`, router, enabled plugin list.                  |
| `src/plugins/projects/`                     | Project list in the sidebar, add/unregister, kanban board page.                             |
| `backend/crates/dashboard-domain`           | `Project`, `ProjectRef`, `ProjectRegistry` — pure, no I/O.                                  |
| `backend/crates/dashboard-persistence`      | `ProjectStore` trait, in-memory store, shared contract test.                                |
| `backend/crates/dashboard-persistence-json` | JSON registry file with atomic writes.                                                      |
| `backend/crates/dashboard-service`          | `ProjectService`: registers folders, opens/seeds kanban-rs workspaces.                      |
| `backend/crates/dashboard-server`           | axum: `/api/projects` + `/api/projects/{id}/kanban/*` → upstream `kanban_server` router.    |
| `backend/crates/dashboard-cli`              | `dashboard` binary.                                                                         |

Dependencies point inward: cli/server → service → persistence → domain. Board data never goes through our own model — it is read and written by the `kanban-*` crates.

## Adding a web plugin

1. Create `src/plugins/<name>/index.tsx` exporting a `DashboardPlugin` (`id`, `name`, `nav`, `routes`, optional `sidebar`).
2. Need server data? `baseApi.injectEndpoints(...)`. Need local state? `createSlice(...).injectInto(rootReducer)` and augment `LazyLoadedSlices`.
3. Add it to the list in `src/app/plugins.ts`.
