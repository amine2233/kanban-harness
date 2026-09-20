---
title: Configuration
---

# Configuration

Three files under the dashboard home (`MVP_DASHBOARD_HOME`, default
`~/.config/mvp-dashboard`). All are read live: edit them by hand, through the web, or with
the CLI — the next request uses the new values, no restart.

## `settings.json` — server settings

```json
{
  "default_storage": "json",
  "cors_origins": ["http://192.168.1.20:5173"]
}
```

| Field             | Meaning                                                                             |
| ----------------- | ----------------------------------------------------------------------------------- |
| `default_storage` | `json` or `sqlite` for newly registered projects                                    |
| `cors_origins`    | browser origins allowed to call the API from another host; empty = same origin only |

Edited from Settings → Server, `dashboard settings set`, or `PATCH /api/settings`.

## `config.yaml` — AI providers

`config.yaml` (or `.yml`) when present, otherwise `config.json`; created on first save.
Read with [swift-configuration](https://github.com/apple/swift-configuration), which also
overlays environment variables.

```yaml
ai:
  default_provider: cc
  provider_ids: [cc, apple, claude]
  providers:
    cc:
      kind: claude_code
      name: Claude Code
      model: sonnet
    apple:
      kind: apple
      name: Apple Intelligence
      model: system
    claude:
      kind: anthropic
      name: Claude API
      model: claude-sonnet-5
      api_key: sk-… # or MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY in the environment
      max_tokens: 2048
      pricing:
        input_per_million: 3
        output_per_million: 15
```

| Field        | Meaning                                                                                              |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| `kind`       | `apple`, `anthropic`, `openai`, `gemini`, `ollama`, `claude_code` — see [Providers](../ai/providers) |
| `model`      | passed to the vendor (`sonnet`, `gpt-5`, `llama3.2`, `system` for Apple)                             |
| `base_url`   | optional; the vendor default otherwise (OpenAI-compatible servers: their `/v1` URL)                  |
| `api_key`    | written to the file with mode `0600`; never returned by the API (only `has_api_key`)                 |
| `max_tokens` | response limit                                                                                       |
| `pricing`    | USD per million input / output tokens; prices a draft when the vendor reports no cost                |

`provider_ids` exists because swift-configuration cannot enumerate keys; keep it in sync
when editing by hand (the web and CLI do).

**Keys from the environment**: `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` overrides the file
and is never written back — the way to keep secrets out of the file entirely.

## Environment variables

| Variable                   | Meaning                                                                       |
| -------------------------- | ----------------------------------------------------------------------------- |
| `MVP_DASHBOARD_HOME`       | the folder above                                                              |
| `MVP_DASHBOARD_PORT`       | API port (tasks)                                                              |
| `MVP_DASHBOARD_HOST`       | bind address                                                                  |
| `MVP_DASHBOARD_URL`        | server the CLI talks to (default `http://127.0.0.1:$MVP_DASHBOARD_PORT`)      |
| `MVP_DASHBOARD_CLAUDE_BIN` | Claude Code executable for `claude_code` providers (default `claude` on PATH) |

## Coming: agent and MCP files

[AI agents](../conceptions/ai-agents) adds `instructions.md` and `agents/*.md`;
[MCP servers](../conceptions/mcp-servers) adds `mcp.json` — same folder, same rules.
