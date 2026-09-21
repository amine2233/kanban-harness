---
title: MCP
---

# MCP — AI agents on your boards

The dashboard is an [MCP](https://modelcontextprotocol.io) server, built on the official
[swift-sdk](https://github.com/modelcontextprotocol/swift-sdk). An AI agent (Claude Code,
Cursor, any MCP client) gets the boards and cards as **tools** and drives the same services
the web and the CLI use — so "in project App, move task-12 to In progress" just works, and
the browser updates live.

MCP is the third client surface, next to the web and the CLI. It is _driven by an AI_, which
is why it has no access to settings, providers or API keys, only to boards and cards.

## Two transports, same tools

| Transport | How                                                    | When                                                        |
| --------- | ------------------------------------------------------ | ----------------------------------------------------------- |
| **stdio** | `dashboard mcp` — the client spawns the process        | the default; nothing exposed on the network                 |
| **HTTP**  | `POST http://127.0.0.1:5175/mcp` on the running server | clients that prefer streamable HTTP; localhost origins only |

Over stdio, `dashboard mcp` behaves like the CLI: when a dashboard server is running the
tools go through it (single writer, browsers update live); otherwise they work on the files.

### Claude Code

```bash
claude mcp add dashboard -- dashboard mcp                                   # stdio
claude mcp add --transport http dashboard http://127.0.0.1:5175/mcp        # HTTP
```

Then, in a Claude Code session: _"list my projects"_, _"create a card 'Fix login crash' in
App's To do column, priority high"_, _"break task-4 down into sub-tasks"_.

## Tools

| Tool                 | Arguments                                                                            | Does                                                             |
| -------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `list_projects`      | —                                                                                    | registered projects                                              |
| `list_boards`        | `project`                                                                            | boards of a project                                              |
| `create_board`       | `project, name, with_default_columns?`                                               | new board, seeded with the default columns unless told otherwise |
| `list_columns`       | `project, board`                                                                     | columns in order, with WIP limits and default statuses           |
| `list_cards`         | `project, board, column?, status?`                                                   | cards, optionally filtered                                       |
| `create_card`        | `project, board, title, column?, description?, priority?`                            | a card (first column by default)                                 |
| `update_card`        | `project, board, card, title?, description?, priority?, status?, points?, due_date?` | change fields; omitted ones are kept                             |
| `move_card`          | `project, board, card, column`                                                       | move; status follows the column's rules                          |
| `delete_card`        | `project, board, card, with_children?`                                               | delete permanently; `with_children` removes its sub-tasks too    |
| `create_subtasks`    | `project, board, card, subtasks: [{title, description?, priority?, points?}]`        | children in the parent's column, linked                          |
| `list_card_children` | `project, board, card`                                                               | a card's sub-tasks with column and status                        |
| `set_card_parent`    | `project, board, card, parent`                                                       | make a card a sub-task (one parent, same board, no cycles)       |
| `remove_card_parent` | `project, board, card`                                                               | detach                                                           |

Conventions the agent can rely on:

- `project` and `board` accept a **name or an id** (case-insensitive; ambiguous names ask for
  the id). `card` accepts an id, a number (`12`) or a key (`task-12`).
- List results are wrapped as `{items, count}`; single results are the object.
- Domain errors (unknown column, WIP limit, relation cycle) come back as **tool errors** with
  the message, never as protocol errors, so the agent can recover.

## Under the hood

`DashboardMCP` holds the tool catalogue (data) and one dispatcher that maps a call to the
command protocols (`ProjectCommands`, `BoardCommands`). The same dispatcher runs in-process
(stdio, no server) or against `RemoteBoardCommands` (stdio with a server, and the HTTP
endpoint inside the server). Nothing in it knows about storage or transport.

## What comes next

[MCP servers and tools](conceptions/mcp-servers): the reverse direction — letting the AI
that drafts tickets _use_ external MCP servers (GitHub, Jira…) as tools, and a per-project
`dashboard mcp --project` that only sees one board.
