# web/ — the frontend

_React 19 + TypeScript + Redux Toolkit over three workspace packages. The Swift server is a separate area: see [`../docs/`](../docs/ARCHITECTURE.md)._

This directory renders and edits boards. It owns no data: the server does, and every byte on
screen came from `/api`. The only local state that survives a reload is the browser settings
in `localStorage`.

## Read first

| File                                           | Open it when                                         |
| ---------------------------------------------- | ---------------------------------------------------- |
| [`docs/PRD.md`](docs/PRD.md)                   | deciding whether something belongs in the app at all |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | you need the store, the plugins or the data flow     |
| [`docs/DESIGN.md`](docs/DESIGN.md)             | you are about to do something a different way        |
| [`docs/RULES.md`](docs/RULES.md)               | before writing code — it is short                    |
| [`docs/MEMORY.md`](docs/MEMORY.md)             | something behaves in a way that makes no sense       |
| [`docs/conceptions/`](docs/conceptions/)       | picking up work — each note carries its tasks        |
| [`docs/DEBUG.md`](docs/DEBUG.md)               | a port is held or a server will not start            |

## Layout

| Path                     | Holds                                                       |
| ------------------------ | ----------------------------------------------------------- |
| `src/app/`               | composition root: store, router, the plugin list            |
| `src/core/`              | shell, the `DashboardPlugin` contract and registry, theme   |
| `src/plugins/`           | `overview`, `projects` (board, card, assistant), `settings` |
| `packages/kanban-model`  | wire types and pure board functions — no React, no Redux    |
| `packages/design-system` | components over purple3 — no store, no domain               |
| `packages/state`         | store, RTK Query endpoints, live socket, AI stream — no JSX |

Imports point one way and ESLint enforces it; the error message names the layer you crossed.

## Commands

| Command              | Gates                                    |
| -------------------- | ---------------------------------------- |
| `pnpm dev`           | Vite on 5173, `/api` proxied to 5175     |
| `pnpm typecheck`     | `tsc -b` over every package              |
| `pnpm lint`          | ESLint, including the layering rules     |
| `pnpm format:check`  | Prettier — covers `docs/` too            |
| `pnpm test`          | Vitest (jsdom)                           |
| `pnpm build`         | typecheck then `vite build` into `dist/` |
| `pnpm test:coverage` | what CI runs                             |

`mise run web:dev`, `web:check`, `web:test`, `web:build` wrap the same things from the repo
root; `mise run dev` starts the backend alongside Vite.

## Rules broken most often

- Layering and package-by-name imports — [R-01, R-02](docs/RULES.md).
- No `fetch` in a component; endpoints live in `packages/state` — [R-03, R-04](docs/RULES.md).
- No `hk-*` or `ds-*` class outside the design system — [R-05](docs/RULES.md).
- No `any` without a comment, and do not weaken `tsconfig.base.json` — [R-08, R-10](docs/RULES.md).
- Every mouse action needs a keyboard equivalent — [R-14](docs/RULES.md).
- Tests stub the server with `stubApi()`, never the hooks or the cache — [R-17](docs/RULES.md).

## Before you finish

`pnpm format:check && pnpm lint && pnpm typecheck && pnpm test` must be green, and `pnpm build`
if you touched types across packages. CI additionally runs `pnpm audit --audit-level=high` and
builds the documentation site, so a new dependency or a broken doc link fails the job without
any change to this directory.
