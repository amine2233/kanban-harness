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

- `config.yaml` is written with mode **0600**. API keys are **write-only**: the API and the
  CLI only ever report `has_api_key`.
- `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` supplies a key from the environment and is
  never written to disk.
- Every write to a project file or settings file is **atomic** (write to a temp file, rename),
  so a crash mid-write cannot corrupt a board.
- Unregistering a project deletes nothing on disk.

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
