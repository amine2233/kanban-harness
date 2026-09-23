---
title: Getting started
---

# Getting started

## Prerequisites

- [mise](https://mise.jdx.dev) installs the pinned toolchain (`mise.toml`: Node 24, pnpm 12,
  Swift 6.3) and provides every task below.
- macOS 14+ (macOS 26 for Apple's on-device model) or Linux with a Swift 6 toolchain.

```bash
mise install          # toolchain
mise run setup        # pnpm install + swift package resolve
```

Without mise: install Node ≥ 22, pnpm 12 and Swift ≥ 6.1 and run the `pnpm` / `swift`
commands the tasks wrap (see `mise.toml`).

## Run it

```bash
mise run dev
```

Starts the API on `http://127.0.0.1:5175` and the web app on `http://localhost:5173` (Vite
proxies `/api`, so there is no CORS to configure). Ctrl-C stops both.

| Task                             | What it does                                                                |
| -------------------------------- | --------------------------------------------------------------------------- |
| `mise run dev`                   | Backend + web dev servers; stale copies on the ports are stopped first      |
| `mise run serve`                 | Build the web app and a release binary, serve both from one process on 5175 |
| `mise run dev:lan` / `serve:lan` | Same, reachable from other machines on your network                         |
| `mise run cli -- …`              | Run the CLI, e.g. `mise run cli -- project list`                            |
| `mise run test`                  | All tests (web + backend)                                                   |
| `mise run check`                 | Everything CI runs                                                          |
| `mise run stop` / `doctor`       | Kill leftover servers / diagnose toolchain, builds and ports                |

Everything binds to loopback by default — the API has no authentication. See
[Security](server/security) before exposing it.

## First project

1. Open the web app, click **+** next to _Projects_ in the sidebar, give a folder path (created
   if missing) and a storage kind (JSON or SQLite).
2. The folder gets a `kanban.json` with one board and the default columns
   **Backlog · To do · In progress · Done**.
3. Add a card with _+ Add card_, or press **✨ Draft with AI** once a provider is configured
   (Settings → AI providers). Apple's on-device model needs no key at all:

```bash
mise run cli -- ai providers add apple --kind apple --model system --name "Apple Intelligence"
```

The same project is visible to the CLI and to AI agents through MCP; a card created from a
terminal appears on the board immediately.

## Environment

Set in `mise.toml`, override in a git-ignored `.env.local`:

| Variable                                  | Default                 | Meaning                                                                                                       |
| ----------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| `MVP_DASHBOARD_HOME`                      | `.local/dashboard-home` | Registry (`projects.sqlite`), `settings.json`, `config.yaml`. Outside mise: `$XDG_CONFIG_HOME/kanban-harness` |
| `MVP_DASHBOARD_PORT`                      | `5175`                  | API port                                                                                                      |
| `MVP_DASHBOARD_HOST`                      | `127.0.0.1`             | Interface to bind; `0.0.0.0` exposes the server on the network                                                |
| `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` | —                       | An AI provider's key from the environment instead of the config file                                          |
| `MVP_DASHBOARD_CLAUDE_BIN`                | `claude`                | The Claude Code executable used by `claude_code` providers                                                    |
