---
title: HTTP API
---

# HTTP API

Base path `/api`. JSON in and out, snake_case, explicit `null`s. Lists are paginated:
`{items, total, page, page_size, total_pages}` (`?page=&page_size=`, max 500). Shapes follow
[kanban-api](https://github.com/kanban-rs/kanban)'s wire format, so tools written for it work
against this server.

## Health and settings

| Method  | Path        | Body / result                                                        |
| ------- | ----------- | -------------------------------------------------------------------- |
| `GET`   | `/health`   | `{"status": "ok"}`                                                   |
| `GET`   | `/settings` | `{default_storage, cors_origins}`                                    |
| `PATCH` | `/settings` | any of the two fields; applied immediately, saved to `settings.json` |

## Projects

| Method   | Path             | Body / result                                                    |
| -------- | ---------------- | ---------------------------------------------------------------- |
| `GET`    | `/projects`      | registered projects                                              |
| `POST`   | `/projects`      | `{name, path, storage?}` → 201; the folder is created and seeded |
| `GET`    | `/projects/{id}` | one project                                                      |
| `PATCH`  | `/projects/{id}` | `{storage: "json" \| "sqlite"}` converts in place                |
| `DELETE` | `/projects/{id}` | unregisters; files are kept                                      |

## Boards, columns, cards

Prefix: `/projects/{id}/kanban/v1`.

| Method   | Path                                | Body / notes                                                  |
| -------- | ----------------------------------- | ------------------------------------------------------------- |
| `GET`    | `/boards`                           |                                                               |
| `POST`   | `/boards`                           | `{name, card_prefix?, with_default_columns?}`                 |
| `PATCH`  | `/boards/{b}`                       | `{name?, description?, position?}`                            |
| `DELETE` | `/boards/{b}`                       |                                                               |
| `POST`   | `/boards/{b}/clone`                 | `{name?}` — deep copy                                         |
| `GET`    | `/boards/{b}/columns`               |                                                               |
| `POST`   | `/boards/{b}/columns`               | `{name, wip_limit?, default_status?}`                         |
| `PATCH`  | `/boards/{b}/columns/{c}`           | `{name?, wip_limit?, default_status?, position?}`             |
| `DELETE` | `/boards/{b}/columns/{c}`           | refused on the last column                                    |
| `GET`    | `/boards/{b}/cards`                 | every card of the board                                       |
| `POST`   | `/columns/{c}/cards`                | `{title, description?, priority?, ai_cost?, subtasks?}` → 201 |
| `PATCH`  | `/boards/{b}/cards/{card}`          | fields; `column_id` moves; `board_id` moves to another board  |
| `DELETE` | `/boards/{b}/cards/{card}`          | `?with_children=true` also deletes its sub-tasks; else they are detached |
| `GET`    | `/boards/{b}/cards/{card}/children` | the card's sub-tasks                                          |
| `PUT`    | `/boards/{b}/cards/{card}/parent`   | `{parent_id}` links, `{parent_id: null}` detaches             |

A card:

```json
{
  "id": "…",
  "board_id": "…",
  "column_id": "…",
  "prefix": "task",
  "card_number": 12,
  "title": "Add password reset",
  "description": "Why…\n\n**Acceptance criteria**\n- [ ] …",
  "priority": "high",
  "status": "todo",
  "position": 0,
  "due_date": null,
  "points": 5,
  "sprint_id": null,
  "ai_cost": {
    "provider": "cc",
    "model": "sonnet",
    "input_tokens": 2,
    "output_tokens": 418,
    "cost_usd": 0.028,
    "estimated": false
  },
  "parent_id": null,
  "children": { "total": 3, "done": 1 },
  "created_at": "…",
  "updated_at": "…",
  "completed_at": null
}
```

`subtasks` on create is `[{title, description?, priority?, points?}]`: children are created in
the same column and linked in the same transaction — if one is invalid, nothing is created.

## AI

| Method   | Path                              | Body / result                                                                                                             |
| -------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `GET`    | `/settings/ai`                    | `{providers: [{id, kind, name, model, base_url, max_tokens, pricing, has_api_key}], default_provider}`                    |
| `PUT`    | `/settings/ai/providers/{id}`     | `{kind, name, model, base_url?, api_key?, max_tokens?, pricing?}` — `api_key` absent keeps the stored key, `""` clears it |
| `DELETE` | `/settings/ai/providers/{id}`     |                                                                                                                           |
| `PUT`    | `/settings/ai/default`            | `{provider_id}`                                                                                                           |
| `POST`   | `/projects/{id}/ai/tickets/draft` | `{idea, board_id, provider?}`                                                                                             |

The draft endpoint answers JSON (`{draft, provider, model, usage}`) — or, with
`Accept: text/event-stream`, **server-sent events**:

| Event     | Data                                                                         |
| --------- | ---------------------------------------------------------------------------- |
| `stage`   | `{step: resolve\|context\|wait\|stream\|validate\|done, detail, elapsed_ms}` |
| `text`    | `{delta}` — raw model output as typed                                        |
| `partial` | the draft so far (any field may be missing)                                  |
| `usage`   | `{input_tokens, output_tokens, cost_usd, estimated}`                         |
| `result`  | `{draft, provider, model, usage}`                                            |
| `error`   | `{code, message}` — the stream ends                                          |

Failures during a stream arrive as an `error` frame on a 200; failures before it (bad body,
unknown project) are normal HTTP errors.

## Events

`GET /events` upgrades to a WebSocket. Messages: `{"kind": "hello"}` on connect, then
`{"kind": "projects_changed" | "workspace_changed" | "settings_changed" | "ai_config_changed",
"project_id"?}`. Clients treat an event as "refetch what this touches".

## MCP

`POST /mcp` — streamable HTTP transport, localhost origins only. See [MCP](../mcp).
