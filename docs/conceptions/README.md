# Conceptions

Design notes written before the code. Each one states the scope that is built first,
what is deliberately left for later, and how the later part is meant to work so it can be
picked up without re-deciding anything.

| Document                                            | Status                                                                            |
| --------------------------------------------------- | --------------------------------------------------------------------------------- |
| [AI agents](ai-agents.md)                           | Global scope planned; per project later                                           |
| [MCP servers and tools](mcp-servers.md)             | Global scope planned; per project later                                           |
| [Hugging Face provider](huggingface-provider.md)    | Planned; implemented by hand                                                      |
| [Provider sign-in](provider-sign-in.md)             | OAuth/PKCE flow, credential store (file / Keychain), OpenRouter then Hugging Face |
| [Live connection](live-connection.md)               | Heartbeat, resume/resync, supervised server — Herdr-style                         |
| [CLI as source of truth](cli-as-source-of-truth.md) | Decided; not yet implemented — daemon owns the data, server/MCP are clients       |

Conventions used in these notes:

- **Global** = the dashboard home (`MVP_DASHBOARD_HOME`, default `~/.config/mvp-dashboard`).
- **Project** = the registered folder holding `kanban.json` / `kanban.sqlite`.
- Files are the source of truth. The web and the CLI edit files; hand edits always win and
  apply on the next request, no restart.
