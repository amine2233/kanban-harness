# Backend Backlog

_Backend only. Frontend tasks: [`web/docs/TASKS.md`](../web/docs/TASKS.md)._

From the `SHOULD` / `MAY` requirements and open questions of [`PRD.md`](PRD.md) and the design
notes in [`conceptions/`](conceptions/). Not scheduled; the order inside a theme is the one its
note already fixed. Size: `S` under a day, `M` a few days, `L` more.

Format: **T-nn (size)** task — PRD id · blocked by · status.

`status` is optional and uses the same `·` separator, so it stays greppable:
`done <sha>`, `dropped: <why>`, `deferred: <why, and what unblocks it>`. A dropped
task keeps its line — deleting it loses the decision.

## Live connection

No heartbeat, no sequence numbers, no replay: a sleep, a proxy reset or a rebuild leaves a
browser stale. Order from `conceptions/live-connection.md`.

- **T-01 (S)** Heartbeat frame and WebSocket ping on a fixed cadence, advertised in `hello`. —
  SRV-17 · —
- **T-02 (M)** Process epoch, per-event sequence number, bounded `ChangeLog` ring (1024). —
  SRV-18 · T-01
- **T-03 (M)** Accept `resume {epoch, seq}`: replay inside the ring, `resync` otherwise. —
  SRV-18 · T-02
- **T-04 (S)** Boundary tests: replay, resync, stale epoch, heartbeat cadence. — SRV-17/18 · T-03
- **T-05 (S)** Restart the backend in `scripts/dev.sh` when it exits non-zero. — SRV-19 · —
- **T-06 (S)** `dashboard server status`: pid, uptime, epoch, socket clients. — SRV-19 · T-02
- **T-07 (S)** Document a launchd plist and a systemd unit with restart-on-failure. — SRV-19 · T-05
- **T-08 (S)** Let the dev client open the socket directly on the backend port (server side:
  confirm the loopback origin rule). — SRV-17 · T-01 · client half in `web/docs/TASKS.md`
- **T-09 (M)** Re-evaluate SSE instead of the WebSocket once T-01…T-03 land. — SRV-17 · T-03

## Robustness

- **T-10 (M)** Migration failures, corrupt files and provider errors become HTTP errors, never
  traps. — SRV-16 · —
- **T-11 (M)** Crash-only test suite: break a project file, hit every route, expect envelopes. —
  SRV-16 · T-10

## AI agents

Named drafting personalities as markdown files, global first. Steps from
`conceptions/ai-agents.md`.

- **T-12 (L)** `DashboardAgents` target: `Agent`, `AgentFile` (front matter round trip keeping
  unknown keys), `AgentStore`, `AgentResolver(home:projectPath:)`; starter agents on first run.
  — SRV-20 · —
- **T-13 (M)** Prompt assembly in the fixed order, knobs rendered as explicit constraints. —
  SRV-20 · T-12
- **T-14 (M)** `streamTicket(agentId:)`: resolve, emit the stage detail, apply provider/model
  overrides, record the agent on the cost entry. — SRV-20 · T-13
- **T-15 (S)** CLI `ai agents list|show|path|default` and `--agent` on `ai ticket`. — CLI-10 · T-14
- **T-16 (M)** API: agent CRUD, default setter, `try` endpoint, `agents_changed` event. —
  SRV-20 · T-14
- **T-17 (S)** MCP `list_agents` and `draft_ticket`. — MCP-04 · T-16 · web editor in `web/docs/TASKS.md`
- **T-18 (S)** Update `README.md`, the site, and the note with what shipped. — DOC-03 · T-17
- **T-19 (M)** Per-project agents under `<project>/.dashboard/`, context files as clipped data,
  resolver tests enabled. — SRV-20 · T-18

## External MCP tools

Letting a drafting agent call GitHub, Jira or a filesystem server. From
`conceptions/mcp-servers.md`.

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

## Provider sign-in

Steps 1–3 shipped (`b85234d`): the OAuth flow, the file credential store, OpenRouter and
Hugging Face.

- **T-26 (M)** `KeychainCredentialStore` on macOS behind `#if canImport(Security)`; the file
  store stays the Linux backend. — SRV-09 · —
- **T-37 (S)** Build the OAuth redirect URI from a configured public URL; when unset, accept
  the `Host` header only if it is loopback. Today a forged `Host` steers OpenRouter's
  `callback_url`, which needs no pre-registration. — SRV-09 · —
- **T-38 (S)** One `registerOpenAICompatible` helper for the three copies of the
  guard-key-then-`OpenAILanguageModel` body (`openai`, `huggingface`, `openrouter`). Keep
  `ProvidersTests.swift:174` passing. — SRV-09 · —
- **T-39 (M)** Renew an expiring token at read time, or carry `expiresAt` on
  `AIProviderConfig`; today only `AssistantService` calls `refreshed()`. — SRV-09 · —
- **T-40 (S)** Record in `ProviderSignInService.signOut` that it does not revoke at the
  vendor. — SRV-09 · —
- **T-41 (M)** `OAuthVendor` descriptor so a vendor is data, not a module. — SRV-09 · T-38 ·
  deferred: one conforming vendor today, OpenRouter deliberately does not fit; revisit at the
  third standard-OAuth vendor

## Cost tracking

- **T-27 (M)** Track a card's cost from backlog to done; the creation entry is already the first
  of a history. — open question · —
- **T-28 (S)** Project totals, once T-27 defines what a total means. — open question · T-27

## Documentation debt

- **T-29 (S)** Fix the stale `README.md` facts: event names, keys in the config file. — DOC-03 · —
- **T-30 (S)** Reconcile the minimum macOS version across README, package and CI. — open
  question · T-33
- **T-31 (S)** Give `conceptions/README.md` a real status per note. — DOC-02 · —

## Decisions needed

Open questions of [`PRD.md`](PRD.md#open-questions); each blocks a task or a theme.

- **T-32 (S)** Are drafting agents a user class of their own? Shapes T-12.
- **T-33 (S)** Pick one product name; the rest become aliases.
- **T-34 (S)** Performance budgets, or declare them out of scope.
- **T-35 (S)** Licence, distribution, versioning.
- **T-36 (S)** Which success criteria become automated checks.
