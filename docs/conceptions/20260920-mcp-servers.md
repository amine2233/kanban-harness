# MCP servers and tools

Two different things share the name:

- **A. The dashboard's own MCP server** — boards and cards as tools for AI clients
  (`dashboard mcp`, `POST /mcp`). Exists today, global.
- **B. External MCP servers** the drafting agents can call as tools (GitHub, Jira, a
  filesystem…). New.

## Scope

- **Built first: global.** One `mcp.json` in the dashboard home; agents can use those servers
  while drafting; the dashboard's server stays global.
- **Later: per project.** A project `mcp.json` replacing servers by name, a trust prompt, and
  a project-scoped dashboard MCP server. Fixed here under _Per-project setup_.

## B. External servers — file

`~/.config/mvp-dashboard/mcp.json`, in the format Claude Code, Cursor and Codex read, so a
block can be copied verbatim between tools:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
    },
    "jira": {
      "type": "http",
      "url": "https://mcp.example.com/sse",
      "headers": { "Authorization": "Bearer ${JIRA_TOKEN}" }
    }
  }
}
```

- `command` + `args` (+ `env`) = stdio server, spawned per draft and stopped after it.
  `type: http` + `url` (+ `headers`) = remote server, connected per draft.
- `${VAR}` is resolved from the dashboard server's environment when connecting. The web never
  receives resolved values and the file is never rewritten with them (same rule as API keys).
- The dashboard's own board tools are the implicit server **`kanban`**, always available and
  bound to the project being drafted for; it is never listed in the file. Exposed to agents
  **read-only** (`list_boards`, `list_columns`, `list_cards`, `get_card`, `list_card_children`):
  creating or moving cards stays a user action, as everywhere else.
- Read on every draft, no restart.

## Agents reference tools

In an agent's front matter (see [20260920-ai-agents.md](20260920-ai-agents.md)):

```yaml
tools: [kanban, github/search_issues, jira/*] # server, server/tool, or server/*
```

No `tools:` = the agent drafts from the board context only (today's behaviour). Unknown
references are reported as warnings in the activity panel, never as failures.

## Running tools while drafting

Two providers paths, one contract:

- **`claude_code` — native.** The resolved servers are written to a temporary file and the CLI
  runs with `--mcp-config <file> --strict-mcp-config --allowedTools mcp__github__search_issues,…`.
  Claude Code runs the tool loop; its `stream-json` reports the calls, which become `tool`
  events. No tool-loop code on our side.
- **AnyLanguageModel providers** (Anthropic, OpenAI, Gemini, Ollama, Apple). ALM sessions take
  `Tool`s; each MCP tool is wrapped as an ALM tool that forwards to `DashboardMCPClient`
  (swift-sdk, client side). ALM runs the loop; the transcript yields the calls.

Contract, both paths:

- New stream event `tool { server, name, arguments (summary), duration_ms, ok, error? }`,
  SSE frame `tool`, CLI `--stream` line `[  812ms] tool github/search_issues 0.8 s`.
- Activity panel: one row per call under _Streaming_ ("github · search_issues · 0.8 s"),
  full arguments/result summary in _Details_, included in _Copy log_.
- `ai_cost.tool_calls` on the card; tokens spent in tool rounds are in the usual counts.

Guard rails: 30 s per call, 12 calls per draft, results clipped to a token budget and passed
as data (the model is told so), the draft validator rejects a ticket carrying URLs or
instructions that were in neither the idea nor a tool result.

## Web, CLI, API (global)

- Settings → **MCP servers**: list from `mcp.json` (name, transport, command/url with `${VAR}`
  shown as written), status after _Test_ (connected · n tools, or the error), editor writing
  the file, _Add server_ / _Remove_.
- Agent editor: tools picker filled from the tested servers' tool lists.
- CLI: `dashboard mcp servers list`, `dashboard mcp servers test <name>`,
  `dashboard mcp servers tools <name>`.
- API: `GET /api/mcp/servers`, `PUT /api/mcp/servers/{name}`, `DELETE …`,
  `POST /api/mcp/servers/{name}/test` → `{ok, tools: [...]}`. Change event
  `mcp_servers_changed`.

## Backend shape

- `MCPConfigStore` in `DashboardAgents` (JSON read/write, `${VAR}` resolution at connect time
  only, atomic writes).
- New target `DashboardMCPClient`: swift-sdk client over stdio / HTTP, `listTools`, `call`
  with timeout, process lifecycle (spawn → use → terminate, never leaked), ALM `Tool` adapter.
- `ClaudeCodeProvider` gains `mcpConfigPath` + `allowedTools`; `AssistantService` resolves the
  agent's tools, opens the clients for the draft, closes them in `defer`.
- Tests: config parsing incl. `${VAR}`; a stub MCP server (swift-sdk server in-process over
  the in-memory transport) exposing one tool; the tool loop through the fake provider; the
  Claude Code path checked on the generated `--mcp-config` file and args; process cleanup.

## Implementation steps (global scope)

1. `mcp.json` + `MCPConfigStore` + `DashboardMCPClient` + CLI `mcp servers list|test|tools`.
2. Tools in drafting: Claude Code via `--mcp-config`; ALM adapters; `tool` events end to end
   (service, SSE, CLI `--stream`, activity panel).
3. API + change event; Settings → MCP servers card; tools picker in the agent editor.
4. Docs.

## A. The dashboard's own MCP server

Today: `dashboard mcp` (stdio) and `POST /mcp` (HTTP, localhost origins); every tool takes a
`project` argument. Unchanged in the global scope, plus two tools: `list_agents` and
`draft_ticket {idea, board, agent?}` (returns the draft, creates nothing).

## Per-project setup (later)

```
<project>/.dashboard/
  mcp.json                        # servers for this project
```

Rules:

- Resolution is `global.mcpServers ∪ project.mcpServers`, **the project wins per server
  name** (replace, not merge: a project `github` entry replaces the global `github` entirely).
- The project file is **read-only in the web**: it is repo content, edited in your editor.
  The web shows it with a `project` / `global` badge per server and _Test_.
- **Trust prompt.** A project `mcp.json` spawns processes from a folder you registered. The
  first time a project's servers are about to be used, the web/CLI asks: "MyApp defines MCP
  servers: github (`npx …`). Trust this project?" The answer is stored in `settings.json`
  (`trusted_projects: [id]`); a changed file re-asks. Global servers are trusted by definition.
- **Project-scoped dashboard server:** `dashboard mcp --project <name|id>` and
  `POST /api/projects/{id}/mcp` expose the same tools **without the `project` argument**,
  bound to that project — a Claude Code session in a repo registers
  `claude mcp add board -- dashboard mcp --project MyApp` and only sees that board.
- CLI: `--project P` on `mcp servers list|test|tools`.
- API: `GET /api/projects/{id}/mcp/servers` (resolved, with sources and trust state),
  `POST /api/projects/{id}/trust`.
- Resolver tests for precedence and trust are written with the global step and enabled here.

## Tasks

Letting a drafting agent call GitHub, Jira or a filesystem server. From
`conceptions/20260920-mcp-servers.md`.

- **T-20 (M)** `mcp.json` in the dashboard home, Claude Code format, `${VAR}` resolved at
  connect time and never written back. — MCP-05 · T-12
- **T-21 (L)** `DashboardMCPClient` target: swift-sdk client over stdio and HTTP, with a stub
  server in tests. — MCP-05 · T-20
- **T-22 (M)** Claude Code path: temporary config, strict-config and allowed-tools flags,
  reported calls become `tool` events. — MCP-05 · T-21
- **T-23 (M)** AnyLanguageModel path: each MCP tool wrapped as an ALM tool, same `tool` events. —
  MCP-05 · T-21
- **T-24 (S)** Guard rails: per-call timeout, per-draft budget, clipped results, read-only board
  tools, `ai_cost.tool_calls`. — MCP-05 · T-23
- **T-25 (M)** Per-project `mcp.json`, trust prompt, `dashboard mcp --project`. — MCP-05 · T-24
