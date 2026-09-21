# @mvp/state

Everything the front end knows about the server and remembers between screens, in one
Redux store. Components import hooks and selectors from here and never call `fetch`.

| Folder       | What it holds                                                                              |
| ------------ | ------------------------------------------------------------------------------------------ |
| `api/`       | RTK Query: one `baseApi` (URL resolved per request from settings) + endpoints per resource |
| `settings/`  | Browser-side settings (server URL, theme), persisted to `localStorage`                     |
| `live/`      | The `/api/events` WebSocket: one socket, reconnect with backoff, cache invalidation        |
| `assistant/` | The streaming AI draft: SSE reader, frames → state, cancel                                 |
| `shell/`     | Sidebar collapsed/expanded                                                                 |
| `testing/`   | `stubApi()` — a `fetch` stub keyed by `METHOD /api/path` for tests (`@mvp/state/testing`)  |

Rules: depends on `@mvp/kanban-model` only; no React components, no DOM beyond
`localStorage`/`WebSocket`/`fetch`; every slice has its selectors exported next to its actions.
