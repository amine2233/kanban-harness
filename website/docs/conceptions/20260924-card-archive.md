---
slug: /conceptions/card-archive
title: Card archive
---

:::note Design note
Where an archived card lives, taking kanban-rs as prior art rather than as a constraint. Source: `docs/conceptions/20260924-card-archive.md`.
:::

The server half of [`web/docs/conceptions/20260924-archived-cards.md`](https://github.com/amine2233/kanban-harness/blob/main/web/docs/conceptions/20260924-archived-cards.md),
which decides the view and blocks every task in it on this one. It also owns the CLI and the
MCP surfaces, because archiving is one operation and three clients.

## kanban-rs already designed this, and that is evidence, not a constraint

`archived_cards` is a section of the format this project started from. kanban-rs is **a starting
example, not a compatibility target for new work** — so what follows is read as prior art from
someone who solved this before us, and it is taken where it is right rather than because it is
theirs.

Its own database says the shape:

```sql
CREATE TABLE archived_cards (
    card_id TEXT PRIMARY KEY,
    board_id TEXT NOT NULL,
    archived_at TEXT NOT NULL,
    original_column_id TEXT NOT NULL,
    original_position INTEGER NOT NULL,
    FOREIGN KEY (card_id) REFERENCES cards(id) ON DELETE CASCADE
);
```

One of its choices is worth keeping, one is not, and one gap is worth filling:

1. **The record carries `original_position`.** The web note remembers the column and forgets
   where in it. Restoring to the top of a column a card sat at the bottom of is a small wrongness
   that is impossible to explain afterwards. Keep it.
2. **The card stays in `cards` — not kept.** `card_id REFERENCES cards(id)` makes the archive a
   marker beside a live row. In this codebase that row is reachable by every operation that
   walks `cards`, and two of them destroy it: see D-2.
3. **There is no batch id.** kanban-rs has no cascade, so it needed none. The web note's D-6 does,
   so we add one — which is exactly the kind of departure being free of the format allows.

What we do keep is **backward** compatibility, which is a different promise: a `kanban.json` this
project has already written must go on loading. Every file written so far has
`archived_cards: []`, and reading an empty section the new way cannot break that.

## Decisions

### D-1 — modelled on the aggregate, serialised back into `extra` — exactly like `spawns`

**Decision.** `Workspace` gains `archivedCards: [ArchivedCard]`, and its `extra` getter rebuilds
`archived_cards` from it on the way out.

This is not a new pattern. `spawns` is already precisely this: a typed array on the aggregate,
carried in `extra` when written, so `KanbanJSONStore` and `FluentWorkspaceStore` keep reading and
writing one dictionary and neither learns a new section. Both keep passing `StoreContract`
without a schema change, and the Fluent backend keeps the section in `workspace_sections`, the
blob it already uses for everything it does not model.

**Rejected.** A `FluentWorkspaceStore` table of its own. It would make the two stores disagree
about what a workspace _is_, and the JSON → SQLite → JSON round trip — a Never break — would
have to learn a special case. The blob is losing nothing here; the aggregate is where the type
belongs.

**Rejected.** Leaving it in the passthrough untouched and filtering on read. Every surface would
re-derive "is this card archived" from an untyped `[String: JSONValue]`, which is how one of
them gets it wrong.

### D-2 — archiving moves the card out of `cards`, into its record

**Decision.** An `ArchivedCard` holds the **whole card** and where it came from:

| Field                | Why                                                 |
| -------------------- | --------------------------------------------------- |
| `card`               | the card as it was — id, number, title, everything  |
| `original_board_id`  | D-6: where it goes back, and what to fall back from |
| `original_column_id` | D-6                                                 |
| `original_position`  | D-6: the place in the column, not only the column   |
| `archived_at`        | the web note's D-7: newest first                    |
| `archive_id`         | D-3: which cards went together                      |

Archiving removes the card from `Workspace.cards` and appends the record. Restoring removes the
record and puts the card back. `Workspace.cards` means _the cards on a board_, and nothing else.

An earlier draft kept the card in `cards`, as kanban-rs does, and hid it with a filter. Read
against this codebase that fails twice:

- **Deleting a column or a board deletes its archived cards.** `deleteColumn` runs
  `cards.removeAll { $0.columnId == id }` and `deleteBoard` the same on `boardId`. A card archived
  from _Review_ dies silently the day _Review_ is deleted — the exact case the web note's D-3
  exists for, and the one way an archive must never lose work.
- **Every read path is wrong by default.** `cards(in:)` drives the WIP limit (`checkWipLimit`),
  new-card positions and compaction, not only what the board shows. An archived card would hold
  a WIP slot in a column nobody can see it in. Fixing that means a filter in every caller, which
  is the shape that gets one wrong.

The earlier draft's case against moving does not survive the code either. The prefix counter is
stored (`Prefix.cardCounter`), not derived from `cards`, and the card number is a field of the
card — moving a card out renumbers nothing. The `spawns` edges keep pointing at an id that is
in the archive, which D-5 relies on.

### D-3 — one archive, one id

**Decision.** `ArchivedCard` carries `archiveId: UUID`. Every card archived by one operation
shares it. Restoring a card restores every record with its `archiveId`.

The web note's D-6 needs to know which children came back with a parent, and the honest way to
record "these went together" is a field that says so. A shared `archived_at` timestamp would do
the same job until the one millisecond in which two archives collide.

**Rejected.** Deriving the batch from the `spawns` links alone. They say who is whose child,
never when they were archived, so a child archived on its own three weeks earlier would come
back with a parent archived today.

### D-4 — `project_id` is a wire field, never a stored one

**Decision.** The API, the CLI and the MCP tools all return `project_id` on an archived card.
Nothing writes it to disk.

A record which does not name its project is useless the moment it leaves the file — a CLI
printing JSON, an MCP tool answering an agent. On disk it would be redundant, because the
workspace file _is_ the project. Both are satisfied by putting it where the record crosses a
boundary and nowhere else.

### D-5 — archiving cascades in one domain operation, and leaves the links alone

**Decision.** `Workspace.archiveCard(id:now:archiveId:)` archives the card and its `spawns`
descendants — one `archivedAt` and one `archiveId` for all of them, each record keeping its own
origin. `now` and `archiveId` are parameters, so the service supplies them from
`@Dependency(\.now)` and `@Dependency(\.uuid)` (R-07).

The web note decided the cascade; this note makes it a single domain operation so no caller can
perform half of it. `Hierarchy` already walks the subtree for delete.

**Archiving does not archive the links.** `deleteCard` stamps `archivedAt` on the `spawns` edges
because the card is about to stop existing. An archived card still exists, so its links stay
live and the structure comes back intact on restore. While a child is archived,
`Hierarchy.children` does not list it, because it reads `cards` — which is the behaviour the
board wants.

### D-6 — restore puts the card back where it was, or says it cannot

**Decision.** `Workspace.restoreCard(id:to:now:)` takes an optional destination column.

- **The card named** goes to the destination when one is given — the web form lets a person
  choose somewhere else — and to its `original_column_id` at `original_position` when not.
- **Every other card in the batch** goes back to its own original column and position, and to
  the destination only when its own column is gone. That is the web note's D-6: one question,
  and no card lands somewhere nobody picked.
- Positions are clamped to the column's current length.
- When a card needs the destination and none was given, the domain throws a `DomainError`
  naming the missing column and restores nothing.

D-2 is what makes this case real: a column can now be deleted under an archived card without
killing it. The web form always sends a destination, because a person is there to choose. The
CLI and an MCP agent may not be, and a silent fallback to "first column" from a non-interactive
caller is how a card ends up somewhere nobody looked.

A restore respects the WIP limit like any other card arriving in a column, and a refused restore
changes nothing.

### D-7 — delete stays exactly as it is

**Decision.** `deleteCard` keeps its behaviour, its `with_children`, and its meaning. Archiving
is added beside it.

A card created by mistake, or one carrying text that should not persist, needs a real delete.
An archived card is not on a board, so `deleteCard` cannot reach it; deleting one from the
archive is a separate operation this note does not add — see § Not in this note.

## The surfaces

One operation, one command-protocol method, three thin call sites:

| Surface | What it gets                                                                                              |
| ------- | --------------------------------------------------------------------------------------------------------- |
| domain  | `Workspace.archiveCard(id:now:archiveId:)`, `restoreCard(id:to:now:)`                                     |
| service | `BoardCommands.archiveCard`, `restoreCard`, `archivedCards` — where every surface already goes            |
| HTTP    | `POST …/cards/:card/archive`, `POST …/archive/:card/restore`, `GET …/archive`                             |
| CLI     | `dashboard card archive <project> <card>`, `dashboard card restore <project> <card> [--board] [--column]` |
| MCP     | `archive_card` and `restore_card`, taking `project, board, card` like `delete_card`                       |

The MCP tools matter more than they look: an agent clearing a finished board has only
`delete_card` today, which is irreversible. That is the single most likely way this project loses
work.

## Tasks

- **T-66 (M)** `ArchivedCard` (the card, its origin, `archived_at`, `archive_id`) on `Workspace`,
  serialised into `extra` like `spawns`; both stores round-trip it and `StoreContract` gains the
  assertion. — SRV-16 · —
- **T-67 (M)** `archiveCard` / `restoreCard` in the domain: the card leaves `cards`, the cascade
  shares one `archiveId`, restore falls back or refuses per D-6. — SRV-16 · T-66
- **T-68 (S)** `BoardCommands` methods and the three routes, `project_id` on the wire. — SRV-16 ·
  T-67
- **T-69 (S)** CLI `card archive` / `card restore`. — CLI-03 · T-68
- **T-70 (S)** MCP `archive_card` / `restore_card`. — CLI-07 · T-68
- **T-71 (S)** A test that a workspace with archived cards written by this code is re-read
  unchanged, and that JSON → SQLite → JSON preserves the section. — SRV-16 · T-66

## Not in this note

- **The view, the menu and the restore form** — the web note.
- **Deleting a card from the archive.** Nothing removes an archived card for good; if it is ever
  wanted it is one more domain operation beside restore.
- **`archived_boards`.** The same kind of section, and absent from the kanban-rs database this
  schema came from, so its shape is unknown. A board is not a card and it needs its own note.
- **Retention.** Nothing expires an archived card.

## Decided

- **kanban-rs compatibility takes the narrow reading** (2026-11-12). The format is where the
  project started, files already written keep loading, and new sections are ours to shape. The
  PRD's broader wording — § Why, the `kanban-rs` v18 principle, the data contract, the Never
  break line and success criterion 2, plus `DESIGN.md` D-03, `ARCHITECTURE.md` and `MEMORY.md` —
  is brought in line by its own change, not by this note.

## Open questions

- **`archived_boards`.** Present in the JSON envelope, absent from the kanban-rs database this
  schema came from. It does not block this note, and it does block the board equivalent.
