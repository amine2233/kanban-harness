# Conceptions

Design notes written before the code. Each one states the scope that is built first,
what is deliberately left for later, and how the later part is meant to work so it can be
picked up without re-deciding anything.

A status below is the note read against the code, not against the intention behind it. Three
values only: **decided, not started**, **decided, partly landed**, **decided and landed**.

| Document                                                | Status                 | Where it stands                                                                                                                                                                                                   |
| ------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI agents](ai-agents.md)                               | decided, not started   | No `DashboardAgents` target, no `agents/` folder, no `default_agent`. Global scope first, per project later — T-12…T-19.                                                                                          |
| [MCP servers and tools](mcp-servers.md)                 | decided, not started   | §B, the external servers an agent can call, is the new part and none of it exists. §A, the dashboard's own server, shipped long before the note and is unchanged — T-20…T-25.                                     |
| [Hugging Face provider](huggingface-provider.md)        | decided and landed     | All six steps, `b85234d`. Its _Not in scope_ — browser sign-in instead of a pasted token — has landed since, under the note below.                                                                                |
| [Provider sign-in](provider-sign-in.md)                 | decided, partly landed | Steps 1–3 and 5 landed (`b85234d`): the OAuth/PKCE flow, the file credential store, OpenRouter and Hugging Face. Step 4, the macOS Keychain store, is T-26. §_Today_ describes the code before the note, not now. |
| [Live connection](live-connection.md)                   | decided, not started   | The server still sends no heartbeat and carries no `epoch`/`seq`, and `scripts/dev.sh` still does not restart the backend — T-01…T-09.                                                                            |
| [CLI as the source of truth](cli-as-source-of-truth.md) | decided and landed     | D-1…D-5 are in (`fed6448`, `422d6fe`): `dashboard daemon`, the handover, one-shot commands through the daemon, `Mode`/`--local`/`--remote` deleted. One open question left, see below.                            |

Where a note and the code disagree, the code is what is true and the note is what needs
fixing. Two of the three open questions in
[CLI as the source of truth](cli-as-source-of-truth.md) are already settled by what shipped:

- **Daemon lifetime** — `DaemonCommand` runs until `dashboard daemon stop`; nothing times it
  out, because the next command would only start it again (T-51).
- **Spawn races** — `DaemonProcess` takes a `daemon.lock` directory under the home before
  spawning, which is the exclusive create the note asked to confirm (T-49).

**Version skew** — an upgraded binary meeting a daemon started by the old one — is the one
still open (T-52).

Conventions used in these notes:

- **Global** = the dashboard home (`MVP_DASHBOARD_HOME`, default `~/.config/mvp-dashboard`).
- **Project** = the registered folder holding `kanban.json` / `kanban.sqlite`.
- Files are the source of truth. The web and the CLI edit files; hand edits always win and
  apply on the next request, no restart.
