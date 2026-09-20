---
title: Architecture
---

# Web app — architecture

The web app is a pnpm workspace: three library packages and one application. Dependencies
only point downwards; a package never imports from the one above it.

```text
src/                    the app: shell, router, plugins (components only)
  │
  ├── @mvp/state        packages/state        Redux store, API endpoints, live socket, AI stream
  │      │
  │      └── @mvp/kanban-model   packages/kanban-model   wire types + pure functions over the board
  │
  └── @mvp/design-system   packages/design-system   UI components over purple3, no state
```

| Package              | Depends on          | Knows about                                   | Never contains                 |
| -------------------- | ------------------- | --------------------------------------------- | ------------------------------ |
| `@mvp/kanban-model`  | nothing             | `Card`, `Column`, drafts, colours, checklists | React, Redux, `fetch`          |
| `@mvp/design-system` | React               | `hk-*`/`ds-*` classes, markdown, icons        | the store, the API, the domain |
| `@mvp/state`         | kanban-model, Redux | the API, settings, the socket, the AI stream  | components, JSX                |
| `src/` (app)         | all three           | pages, dialogs, the board, the shell          | `fetch`, hand-written CSS      |

## How a feature flows through the layers

Take "move a sub-task to another column":

1. **`@mvp/kanban-model`** — `buildBoardIndex(cards, columns)` already knows the card's parent,
   its column name and its family colour. Pure function, tested with plain data.
2. **`@mvp/state`** — `useMoveCardMutation()` (in `api/kanbanApi.ts`) sends the `PATCH`; the
   `Card` tag is invalidated so the list refetches; the server also pushes a `board_changed`
   event through the socket (`live/`) which invalidates the same tag for every open browser.
3. **`src/plugins/projects/board/`** — `KanbanColumn` handles the drop, calls the mutation;
   `KanbanCard` reads the index to show the breadcrumb and the colour. No logic beyond wiring.

Rule of thumb when adding code: _does it need the DOM or React?_ No → `kanban-model`
(if it is about board data) or `state` (if it is about fetching/remembering). Yes, and it is
reusable and knows nothing about kanban → `design-system`. Otherwise → the plugin.

The layering is **enforced by ESLint** (`no-restricted-imports` blocks in `eslint.config.js`):
`kanban-model` cannot import React or Redux, `design-system` cannot import the store or the
domain, `state` cannot import React components, and the app must import packages by name,
never by path. A wrong import fails `pnpm lint` (and CI) with a one-line explanation.

Each package has its own `tsconfig.json` (extending `tsconfig.base.json`) so it type-checks
alone: `pnpm exec tsc -p packages/state/tsconfig.json --noEmit`.

## The app (`src/`)

```text
src/app/            App.tsx (router + store provider), plugins.ts (the plugin list)
src/core/plugin/    the DashboardPlugin contract and the registry
src/core/shell/     top bar, sidebar, server status
src/core/settings/  theme hook and picker (the setting itself lives in @mvp/state)
src/plugins/
  overview/         landing page
  settings/         Settings page and its cards
  projects/
    board/          KanbanBoard → KanbanColumn → KanbanCard, tabs, columns, drag and drop
    card/           CardDialog = shell; cardForm.ts = the form as a pure reducer; fields, sub-task rows, relations
    assistant/      DraftWithAI (form) + ActivityPanel (view) over tracker.ts (pure view model)
```

Pattern used everywhere: **a pure module next to the component**. `cardForm.ts`, `tracker.ts`,
`boardIndex.ts` hold the decisions; the `.tsx` next to them only renders. Tests target the
pure module first (fast, no DOM) and the component second (one behaviour test per screen).

## Testing

- `pnpm test` runs every package (`packages/*/src/**/*.test.*` and `src/**/*.test.*`).
- UI tests stub the server with `stubApi()` from `@mvp/state/testing`: a `fetch` stub keyed by
  `METHOD /api/path`, which also answers server-sent events for the AI stream.
- Pure modules are tested with plain objects — no rendering, no store.

## Adding a plugin

1. Endpoints and state go in `packages/state` (a file under `api/`, exported from `index.ts`).
2. Pure helpers go in `packages/kanban-model` when they are about board data.
3. `src/plugins/<name>/index.tsx` exports a `DashboardPlugin` (`id`, `name`, `nav`, `routes`,
   optional `sidebar`); add it to `src/app/plugins.ts`.
