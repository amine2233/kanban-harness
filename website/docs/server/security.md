---
title: Security
---

# Security

This is a personal tool: **there is no authentication**. Anyone who can reach the port can
read and change every board and every setting. The defaults are chosen so that "reach the
port" means "is on this machine".

## Network

- The server and the web dev server bind to **loopback** (`127.0.0.1`). Nothing is reachable
  from the network unless you ask (`serve:lan`, `dev:lan`, `MVP_DASHBOARD_HOST=0.0.0.0`).
- **CORS is opt-in** and read live from `settings.json` (`cors_origins`). Same origin needs
  nothing; the dev proxy keeps the browser on one origin.
- The MCP HTTP endpoint accepts **localhost origins only**.
- If you expose the server on a LAN, treat it like an open share: anyone on that network
  is you.

## Files and secrets

Secrets are kept apart from settings, so the settings file can be shared and the secret file
cannot be shared by accident.

| File                      | Holds                                        | Mode   |
| ------------------------- | -------------------------------------------- | ------ |
| `<home>/config.yaml`      | providers, models, base URLs — and no secret | `0600` |
| `<home>/credentials.json` | API keys and OAuth tokens                    | `0600` |

Both are written **atomically** — to a temporary file, then renamed — as is every project and
settings file, so a crash mid-write cannot corrupt one.

Neither exists until something writes it. A fresh home holds only `projects.sqlite` and
`daemon.port`; `credentials.json` appears at the first sign-in or the first key stored, and the
config file at the first `dashboard ai providers add`. So "I cannot find `credentials.json`"
usually means no provider has been configured in that home — check which home you are in with
`dashboard daemon status`.

The config file is read as `config.yaml`, `config.yml` or `config.json`, whichever exists; when
none does, a first save writes `config.json`.

**Where a provider's key comes from**, in order: the environment variable
`MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY`, then `credentials.json`, then a literal `api_key:`
in `config.yaml` (kept for existing files). A key that came from the environment is **never
written to disk** — deliberately, so a CI runner or a shared machine can supply one that leaves
no trace.

:::caution The environment path and the daemon
The daemon inherits the environment of whichever command started it, and then outlives every one
of them. A key exported in one shell therefore lasts exactly as long as that daemon: replace it
from a shell that never exported the key, and the provider reports itself unconfigured with no
further explanation. Put the value in `config.yaml` — which is read per request — or
`dashboard daemon stop` first. See [Daemon](../daemon).
:::

Keys are **write-only** across every surface: the API, the CLI and the web app only ever report
`has_api_key`. A secret never appears in a log line, at any level.

Unregistering a project deletes nothing on disk.

### What is planned

Two design notes decide where this goes next, and neither is implemented yet:

- **[Config secret references](../conceptions/config-secret-references)** — `api_key: ${VAR}` in
  `config.yaml`, resolved on read from the process environment or a `.env` in the home, so the
  configuration file references a secret instead of containing one, and a key stops depending on
  the shell that happened to start the daemon.
- **[The token store](../conceptions/oauth-token-store)** — OAuth access and refresh tokens
  sealed with AES-GCM under a key generated on first use, because a token the dashboard obtained
  is the one secret that cannot be referenced from somewhere else.

Both notes also decide two things worth knowing in advance: a home created inside a repository
gets a `.gitignore`, since everything secret lives in the home and a key committed to a history
cannot be revoked; and `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` becomes redundant once `${VAR}`
reads the process environment, so it is deprecated with a warning rather than removed.

## AI

- The assistant **only proposes**. A draft becomes cards only when a person presses Create
  (or passes `--create` on the CLI); nothing is written to a board behind your back.
- Board text (card titles, descriptions) is sent to the model as **data**, inside delimiters,
  with a system prompt stating it must never be read as instructions — a card containing
  "ignore previous instructions" does not get to steer the draft.
- The draft is **validated** before it reaches you: title length, priority enum, points range,
  sub-task count; anything else is rejected with `AI_BAD_OUTPUT`.
- `claude_code` runs the Claude Code CLI with **tools disabled** (`--tools ""`,
  `--strict-mcp-config`) and no session persistence; it can only answer.

## MCP agents

An AI agent connected through MCP can create, move and delete cards — that is the point.
It cannot change settings, providers or projects' storage, and it cannot read API keys.
Give an agent the **stdio** transport (`dashboard mcp`) so nothing is exposed over HTTP at all.

## What is not done (yet)

No users, no tokens, no audit log. If you need to share a dashboard between people, put it
behind a reverse proxy that authenticates, and remember that everyone behind it is one
identity.
