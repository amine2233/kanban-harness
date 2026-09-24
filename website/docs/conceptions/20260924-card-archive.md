---
slug: /conceptions/card-archive
title: Card archive
---

:::note Design note
Where an archived card lives, given that kanban-rs already designed the section. Source: `docs/conceptions/20260924-card-archive.md`.
:::

The server half of [`web/docs/conceptions/20260924-archived-cards.md`](https://github.com/amine2233/kanban-harness/blob/main/web/docs/conceptions/20260924-archived-cards.md),
which decides the view and blocks every task in it on this one. It also owns the CLI and the
MCP surfaces, because archiving is one operation and three clients.

## kanban-rs already designed this

`archived_cards` is not an empty extension point waiting for us. It is a section of a format we
do not own, and [`PRD.md`](https://github.com/amine2233/kanban-harness/blob/main/docs/PRD.md) lists _a written `kanban.json` opens in `kanban-rs`_ under
**Never break**. Its own database says what the shape is:

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

Three things follow, and each corrects an assumption in the web note:

1. **The card is kept.** `card_id REFERENCES cards(id)` — an archived card is still a row in
   `cards`. Archiving is a _marker_, not a move, and `cards` carries no `archived` flag: a card
   is archived exactly when a record names it.
2. **The record carries `original_position`.** The web note remembers the column and forgets
   where in it. Restoring to the top of a column a card used to sit at the bottom of is a small
   wrongness that is impossible to explain afterwards.
3. **There is no batch id and no project id.** D-6 of the web note wants the first and the review
   asked for the second. Neither can be a new column in someone else's table.

## Decisions

### D-1 — modelled on the aggregate, serialised back into `extra` — exactly like `spawns`

**Decision.** `Workspace` gains `archivedCards: [ArchivedCard]`, and its `extra` getter rebuilds
`archived_cards` from it on the way out.

This is not a new pattern. `spawns` is already precisely this: a typed array on the aggregate,
carried in `extra` when written, so `KanbanJSONStore` and `FluentWorkspaceStore` keep reading and
writing one dictionary and neither learns a new section. Both keep passing `StoreContract`
without a schema change, and the Fluent backend keeps the section in the same blob it already
uses for everything it does not model.

**Rejected.** A `FluentWorkspaceStore` table of its own. It would make the two stores disagree
about what a workspace _is_, and the JSON → SQLite → JSON round trip — a Never break — would
have to learn a special case. The blob is losing nothing here; the aggregate is where the type
belongs.

**Rejected.** Leaving it in the passthrough untouched and filtering on read. Every surface would
re-derive "is this card archived" from an untyped `[String: JSONValue]`, which is how one of
them gets it wrong.

### D-2 — an archived card is hidden by a record, not by leaving the board

**Decision.** `Workspace.cards` keeps the card. Everything that lists cards for a board filters
out the ones an `ArchivedCard` names.

Following kanban-rs here is not deference, it is the cheaper design: a card that leaves `cards`
breaks every `spawns` edge pointing at it, every prefix counter, and the card number that makes
`task-12` mean something. Keeping it makes restoring a matter of deleting a record.

The consequence to watch is the inverse: **every read path is now wrong by default.** A list that
forgets the filter shows archived cards on the board, which looks like archiving silently failing.
The filter belongs in one place — the domain query the routes already use — and not in each
caller.

### D-3 — `archived_at` is the batch key; no invented field

**Decision.** Every card archived by one operation is stamped with the **same** `archived_at`.
Restoring a parent restores the archived cards sharing its timestamp that its `spawns` history
links to it.

The web note's D-6 needs to know which children came with a parent. kanban-rs's record has no
place for an id, and adding a key inside an entry of a format we do not own is the thing the
PRD forbids. A shared timestamp carries the same information using only fields that already
exist.

**The risk, stated rather than hidden:** two unrelated archives in the same instant would merge
into one batch. `archived_at` is RFC3339 with sub-second precision and the daemon is the only
writer, so this needs two operations inside the same millisecond on one machine. If it ever
matters, the fallback is an extra key inside the entry — **which requires first verifying that
kanban-rs preserves unknown keys there**, and that check is an open question below, not an
assumption.

### D-4 — `project_id` is a wire field, never a stored one

**Decision.** The API, the CLI and the MCP tools all return `project_id` on an archived card.
Nothing writes it to disk.

The review is right that a record which does not name its project is useless the moment it
leaves the file — a CLI printing JSON, an MCP tool answering an agent. It is also true that on
disk it would be redundant, because the workspace file _is_ the project, and there is no column
for it in a schema we must stay compatible with. Both are satisfied by putting it where the
record crosses a boundary and nowhere else.

### D-5 — archiving cascades; the domain does it in one operation

**Decision.** `Workspace.archiveCard(id:now:)` archives the card and its `spawns` descendants,
one timestamp for all of them. Restoring takes the batch.

The web note decided the cascade; this note makes it a single domain operation so no caller can
perform half of it. `Hierarchy` already walks the subtree for delete, and `deleteCard` already
archives the links, so both halves exist.

**Archiving does not archive the links.** `deleteCard` stamps `archivedAt` on the `spawns` edges
because the card is about to stop existing and the history is all that survives. An archived
card still exists, so its links stay live — and they have to, because D-3 uses them to find the
children on the way back.

### D-6 — restore puts the card back where it was, or says it cannot

**Decision.** Restore takes an optional board and column. With none, the record's
`original_column_id` and `original_position` are used. When that column is gone, the caller must
supply one; the domain refuses rather than guessing.

The web note's form supplies them because a person is there to choose. The CLI and an MCP agent
may not be, and a silent fallback to "first column" from a non-interactive caller is how a card
ends up somewhere nobody looked. A `DomainError` naming the missing column is a better answer
than a surprising board.

### D-7 — delete stays exactly as it is

**Decision.** `deleteCard` keeps its behaviour, its `with_children`, and its meaning. Archiving
is added beside it.

A card created by mistake, or one carrying text that should not persist, needs a real delete —
and `ON DELETE CASCADE` in kanban-rs's own schema says deleting an archived card removes its
record too, which is the behaviour we already get by keeping the record keyed on the card.

## The surfaces

One operation, one command-protocol method, three thin call sites:

| Surface | What it gets                                                                                              |
| ------- | --------------------------------------------------------------------------------------------------------- |
| domain  | `Workspace.archiveCard(id:now:)`, `restoreCard(id:to:)`, and the filter D-2 names                         |
| service | `BoardCommands.archiveCard`, `restoreCard`, `listArchivedCards` — where every surface already goes        |
| HTTP    | `POST …/cards/:card/archive`, `POST …/archive/:card/restore`, `GET …/archive`                             |
| CLI     | `dashboard card archive <project> <card>`, `dashboard card restore <project> <card> [--board] [--column]` |
| MCP     | `archive_card` and `restore_card`, taking `project, board, card` like `delete_card`                       |

The MCP tools matter more than they look: an agent clearing a finished board has only
`delete_card` today, which is irreversible. That is the single most likely way this project loses
work.

## Tasks

- **T-66 (M)** `ArchivedCard` on `Workspace`, serialised into `extra` like `spawns`; both stores
  round-trip it and `StoreContract` gains the assertion. — SRV-16 · —
- **T-67 (M)** `archiveCard` / `restoreCard` in the domain, cascade and the one shared timestamp;
  the board query filters archived cards. — SRV-16 · T-66
- **T-68 (S)** `BoardCommands` methods and the three routes, `project_id` on the wire. — SRV-16 ·
  T-67
- **T-69 (S)** CLI `card archive` / `card restore`. — CLI-03 · T-68
- **T-70 (S)** MCP `archive_card` / `restore_card`. — CLI-07 · T-68
- **T-71 (S)** A test that a workspace with archived cards written by this code is re-read
  unchanged, and that JSON → SQLite → JSON preserves the section. — SRV-16 · T-66

## Not in this note

- **The view, the menu and the restore form** — the web note.
- **`archived_boards`.** The same kind of section, and absent from the kanban-rs database this
  schema came from, so its shape is unknown. A board is not a card and it needs its own note.
- **Retention.** Nothing expires an archived card.

## Open questions

- **The JSON v18 shape of an `archived_cards` entry.** The schema above is kanban-rs's SQLite;
  the JSON envelope is a different serialisation of the same idea and the mapping is assumed,
  not verified — every `archived_cards` array on this machine is empty. Archive one card in
  kanban-rs and read the file before cutting T-66 into patches. If the field names differ, this
  note's decisions all hold and only the codec changes.
- **Does kanban-rs preserve unknown keys inside an entry?** D-3's fallback depends on it, and so
  does any future field. Worth knowing before it is needed rather than during an incident.
- **`archived_boards` is absent from that database but present in the JSON envelope.** Either the
  two are different versions or the section is JSON-only. It does not block this note, and it
  does block the board equivalent.
