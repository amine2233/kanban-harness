# Web App Memory

_Frontend only. Backend traps: [`docs/MEMORY.md`](../../docs/MEMORY.md)._

Things that cost an afternoon once. Rewrite an entry when it stops being true.

### `website/docs/web/architecture.md` is partly stale

It claims the frontend receives events but does not process them — `liveMiddleware` has
invalidated tags on every frame for a while. It also gives wrong dashboard-home paths, quotes
different default column names than the README, and links a `DATABASE_FIX_PLAN.md` that does
not exist. Trust the code, then fix that page (T-16).

### Event frames are snake_case on the wire

The client parses `hello`, `projects_changed`, `workspace_changed`, `settings_changed`,
`ai_config_changed` with a `project_id`; the server's enum is camelCase internally. Writing a
client against the Swift case names matches nothing. (`packages/state/src/live/events.ts`)

### Buttons inside a card break dragging

A card is a `draggable` `<li>`; every interactive element inside it stops `mousedown` and
`click` propagation, and the card suppresses text selection. Three commits went into this
(`9e0780a`, `2afb32d`, `005703a`) — adding a control to `KanbanCard` without the same handlers
silently disables the drag.

### State resets by key, not by effect

`ProjectPage` keys the board by project id and the columns by `projectId-boardId`. Resetting
selection in an effect renders once with the previous project's data first; that was the bug in
`9462643`.

### The socket drops on every backend rebuild

The server process owns it and the dev proxy adds its own resets; there is no heartbeat and no
replay yet, so a stale board in development is expected. Backoff is 1s → 30s, with no fast path
on tab focus. (`docs/conceptions/live-connection.md`)

### TypeScript is stricter than most React codebases

`strict` plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `noUnusedLocals`,
`verbatimModuleSyntax`, `erasableSyntaxOnly` ([`tsconfig.base.json`](../tsconfig.base.json)),
and `tseslint.configs.strictTypeChecked` on top. An optional prop passed as `undefined` is an
error, not a no-op — that class of failure is what `b2b46d1` cleaned up.

### The layering is a lint error, not a convention

`kanban-model` cannot import React or Redux, `design-system` cannot import the store,
`state` cannot import React, and the app cannot import a package by path. The message tells you
which layer you crossed. (`eslint.config.js`)

### Each package type-checks alone

`pnpm typecheck` is `tsc -b` over project references; a package with its own `tsconfig.json`
can be checked on its own. A type that compiles in the app but not in a package means an import
crossed a layer.

### Tests stub `fetch`, keyed by method and path

`stubApi({ 'GET /api/projects': … })` ignores the query string and can answer SSE frames. A
test that fails with "Request failed" usually lacks a route key, not a fixture field.
(`packages/state/src/testing/fakeApi.ts`)

### CI runs more than `pnpm test`

`pnpm audit --audit-level=high`, `format:check`, `lint`, `typecheck`, `test:coverage`, `build`,
and the website build. A high-severity advisory in a transitive dependency fails the job with
no code change. (`.github/workflows/ci.yml`)

### Dev ports and the proxy

Vite on 5173 proxies `/api` to `127.0.0.1:5175` with `ws: true`. Ports come from
`MVP_DASHBOARD_WEB_PORT` and `MVP_DASHBOARD_PORT` in `mise.toml`; `mise run dev` starts both and
refuses to run when a foreign process holds a port. Forensics: [`DEBUG.md`](DEBUG.md).

### The CSP is build-only

`cspPlugin` injects a meta tag at build time; the dev server has none, and there are no HTTP
security headers because nothing serves them yet. Marked `ponytail:` in `vite.config.ts`.

### Browser settings live under one key

`localStorage['mvp-dashboard.settings']` holds `serverUrl` and `theme`, written by a store
subscription. An empty `serverUrl` means same origin. Clearing site data resets both.
