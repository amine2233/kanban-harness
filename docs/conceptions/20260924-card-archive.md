# Where an archived card lives

The server half of [`web/docs/conceptions/20260924-archived-cards.md`](../../web/docs/conceptions/20260924-archived-cards.md),
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

Two of its choices are worth keeping, and one gap is worth filling:

1. **The card is kept.** `card_id REFERENCES cards(id)` — an archived card is still a row in
   `cards`, and `cards` carries no `archived` flag. We reach the same conclusion from our own
   code, which is why it is D-2 rather than an import: a card that leaves the collection breaks
   every `spawns` edge pointing at it, the prefix counter, and the card number that makes
   `task-12` mean something.
2. **The record carries `original_position`.** The web note remembers the column and forgets
   where in it. Restoring to the top of a column a card sat at the bottom of is a small wrongness
   that is impossible to explain afterwards. Keep it.
3. **There is no batch id.** kanban-rs has no cascade, so it needed none. The web note's D-6 does,
   so we add one — which is exactly the kind of departure being free of the format allows.

What we do keep is **backward** compatibility, which is a different promise: a `kanban.json` this
project has already written must go on loading. Adding a section nothing used to read cannot
break that.

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

### D-3 — one archive, one id

**Decision.** `ArchivedCard` carries `archiveId: UUID`. Every card archived by one operation
shares it. Restoring a parent restores the records with that id.

The web note's D-6 needs to know which children came back with a parent, and the honest way to
record "these went together" is a field that says so. An earlier draft of this note used the
shared `archived_at` timestamp as the key, to avoid adding a field to a format we did not own —
with kanban-rs demoted to prior art, that constraint is gone and the cleverness with it. A
timestamp used as an identity is a collision waiting for the one millisecond that matters.

**Rejected.** Deriving the batch from the `spawns` links alone. They say who is whose child,
never when they were archived, so a child archived on its own three weeks earlier would come
back with a parent archived today.

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

- **The PRD still promises kanban-rs compatibility, in seven places.** A value proposition
  (§ Why), a principle ("`kanban.json` stays valid `kanban-rs` v18"), the data contract, a
  **Never break** line, and success criterion 2 ("a project created here opens unchanged in the
  `kanban-rs` CLI/TUI") — plus `DESIGN.md` D-03, `ARCHITECTURE.md` and `MEMORY.md`. This note
  assumes the narrow reading: the format is where the project started, existing files keep
  loading, and new sections are ours to shape. The broad reading — dropping the promise outright
  — deletes a success criterion and a differentiator, and that is a PRD change, not a note's to
  make. It needs deciding before T-66, because it decides whether `archive_id` is simply a field
  or a deliberate divergence worth recording.
- **`archived_boards`.** Present in the JSON envelope, absent from the kanban-rs database this
  schema came from. It does not block this note, and it does block the board equivalent.
