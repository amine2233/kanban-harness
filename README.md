# MVP Dashboard

React 19 + TypeScript + Redux Toolkit dashboard shell with a plugin architecture, styled with Heroku's [purple3](https://design.herokai.com/purple3/).

```sh
pnpm install
pnpm dev
```

## Layout

| Path                 | Role                                                                                                                       |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `src/design-system/` | Reusable components wrapping purple3 classes (`Button`, `Card`, `Input`, …). The only place that knows `hk-*` class names. |
| `src/core/plugin/`   | `DashboardPlugin` contract + registry (nav + routes).                                                                      |
| `src/core/shell/`    | App chrome: top bar, sidebar, layout, `shell` slice.                                                                       |
| `src/app/`           | Composition root: store, router, enabled plugin list.                                                                      |
| `src/plugins/*`      | Self-contained features. Each exports a `DashboardPlugin`.                                                                 |

## Adding a plugin

1. Create `src/plugins/<name>/index.tsx` exporting a `DashboardPlugin` (`id`, `name`, `nav`, `routes`).
2. Need state? Create a slice and inject it: `export const slice = createSlice(...).injectInto(rootReducer)` — selectors are then typed against `RootState`.
3. Add it to the list in `src/app/plugins.ts`.
