# website/ — the published documentation

_The Docusaurus site users read. The agent-facing docs are [`../docs/`](../docs/) (backend) and [`../web/docs/`](../web/docs/) (frontend); the three sets must not contradict each other._

Pages describe behaviour that exists. If the code and a page disagree, the code wins and the
page is the bug.

## Layout

| Path                   | Holds                                                                 |
| ---------------------- | --------------------------------------------------------------------- |
| `docs/`                | the content: `index`, `getting-started`, `architecture`, `cli`, `mcp` |
| `docs/server/`         | overview, API, configuration, security                                |
| `docs/web/`            | features, AI drafting, web architecture                               |
| `docs/ai/`             | providers, streaming and cost                                         |
| `docs/conceptions/`    | copies of `../docs/conceptions/*.md` with front matter added          |
| `sidebars.ts`          | the navigation tree — a page not listed here is unreachable           |
| `docusaurus.config.ts` | site config; `onBrokenLinks: 'throw'`, Mermaid enabled                |
| `src/`, `static/`      | theme CSS and images                                                  |

The conception pages are copies: edit `../docs/conceptions/` and re-copy, never the other way.

## Adding or moving a page

Create the file under `docs/`, give it front matter with at least `title:`, add its id to
`sidebars.ts`, and link between pages with relative doc ids (`../server/api`, `getting-started`)
as the existing pages do. `routeBasePath` is `/`, so `docs/index.md` is the home page.

## Commands

`mise run docs` serves it on `http://localhost:3000` with live reload. `mise run docs:build`
is the real gate: broken links and broken Markdown links throw, and CI runs it on every push.
`pnpm --filter website typecheck` checks the TypeScript config files.

## Rules

- Document what exists; a planned feature goes to `docs/conceptions/`, not to a reference page.
- A behaviour change updates its page in the same change ([R-36](../docs/RULES.md)).
- Keep the front matter, heading style and link style of the surrounding pages.
- Prettier covers this folder; run `npx prettier --write` on what you touch.
- Publishing is automatic on `main` via `.github/workflows/docs.yml`; do not hand-deploy.

## Known stale

`docs/web/architecture.md` states the frontend ignores change events (it does not), gives
dashboard-home paths that do not match the configuration, shows a plugin shape that is not the
real `DashboardPlugin`, and links a file that does not exist. `docs/web/features.md` names
different default columns than the root `README.md`. Both are tracked as
[`../web/docs/TASKS.md`](../web/docs/TASKS.md) T-16 — do not copy from those pages without
checking the code.
