---
title: Features
---

# Web app — features

## Projects

The sidebar lists your projects. **+** registers a folder: give a path (created if missing),
an optional name and the storage kind — JSON (`kanban.json`, readable by the kanban-rs
CLI/TUI) or SQLite (`kanban.sqlite`). The folder is seeded with one board and the default
columns **Backlog · To do · In progress · Done**.

The project page header lets you **switch storage** (converted in place, the old file is kept)
or **Unregister** the project (files on disk are never deleted).

## Boards and columns

- Boards are tabs at the top of the project page: _+ New board_, and per board a ⋯ menu with
  _Rename_, _Add column_, _Duplicate_, ← → reorder and _Delete_ (with confirmation).
- Each column has a ⋯ menu: edit name, WIP limit and default status; ← → reorder; delete (a
  board keeps at least one column). A column over its WIP limit is highlighted.
- Columns have a fixed width; the board scrolls horizontally.

## Cards

A card shows what matters at a glance, never the whole description:

| On the card            | Meaning                                                               |
| ---------------------- | --------------------------------------------------------------------- |
| coloured left edge     | the card's _family_: a parent and its sub-tasks share one flat colour |
| priority dot           | low · medium · high · critical                                        |
| `task-12`              | the card key (board prefix + number)                                  |
| `5 pt`                 | story points                                                          |
| `24 Dec` (red if late) | due date                                                              |
| `☑ 2/5`                | acceptance criteria done / total, read from the markdown checklist    |
| `≡`                    | has a description without a checklist                                 |
| `✨ $0.03`             | drafted with AI; hover for provider and model                         |
| `⌥ 1/4`                | sub-tasks done / total                                                |

- **Drag** a card to another column, or use the ← → arrows that appear on hover.
- Click a card to open it: title, description (see below), priority, status, board, column,
  due date, points; **Delete** asks for confirmation — a parent card offers a checkbox to
  delete its sub-tasks too (otherwise they stay on the board, unlinked).
- Moving a card into a column that has a default status applies it (moving into _Done_
  sets `done` and the completion date, exactly like kanban-rs).

### Descriptions are markdown

The description field has **Write / Preview** tabs (GitHub-flavoured markdown: checklists,
tables, code). Ticking a `- [ ]` item in the preview updates the text and, on an existing
card, saves it straight away — so the AI's acceptance criteria become a checklist you work
through, and the card's `☑ 2/5` updates on the board.

### Sub-tasks

A card can have sub-tasks: cards of their own that live in whatever column they are in and
stay linked to their parent.

- On the board, a sub-task carries a breadcrumb `⌥ task-2 · parent title` (click to open the
  parent); the parent shows a _Sub-tasks 1/4_ list with each child's column.
- Move a sub-task like any card — it keeps its parent.
- In the dialog, a parent lists its children (click to open) and a child links to its parent.
- Rules: one parent per card, same board, no cycles. Deleting a card or moving it to another
  board detaches its links (they are archived, not lost — kanban-rs semantics).
- Sub-tasks are proposed by the AI when a ticket is too big for one card, or created through
  the API/MCP.

## Draft with AI

Described in [AI drafting](ai-drafting).

## Live updates

The app keeps one WebSocket to `/api/events`. Any change made by the CLI, an AI agent through
MCP, or another browser refreshes the affected view immediately. The top bar shows the
connection state; the socket reconnects with backoff and follows a server URL change.

## Settings

- **This browser** — the API server URL this browser talks to (empty = same origin), with a
  _Test connection_ button. Stored in `localStorage`.
- **Appearance** — _System_ / _Light_ / _Dark_; _System_ follows the OS and switches live. A
  compact switch also sits in the top bar.
- **Server** — `settings.json` on the server: default storage for new projects, allowed
  browser origins (CORS). Applied immediately, no restart.
- **AI providers** — the providers in `config.yaml`: kind, model, base URL, API key
  (write-only), max tokens, pricing. See [Providers](../ai/providers).
