# Archived cards, and putting one back

A card can only be **deleted** today — irreversibly, with `with_children` as the only option —
and that is the single way to get one off a board. This note decides the view that lists what
has been archived and the interaction that restores a card to a board.

It does not decide where an archived card is stored. The app owns no data
([`../../AGENT.md`](../../AGENT.md)): every byte on screen came from `/api`. So this note states
the contract it needs and stops there — see § What this needs from the server, which is a
backend note and blocks every task below.

## Today

Nothing is archived. The word appears in the codebase exactly once with this meaning:
`Workspace.deleteCard` calls `archiveSpawns`, which stamps `archivedAt` on the card's
parent/child links and keeps them as history, the way kanban-rs does. The card itself is dropped.

`archived_cards` exists in the file format and is **not modelled**: `KanbanJSONStore` seeds the
key when it is missing so a round-trip is byte-stable, and `Workspace` carries it in `extra`
untouched. The Fluent backend keeps the same sections as an opaque blob. Whatever the backend
note decides, both stores have to keep passing `StoreContract`.

On the client, `kanbanApi.deleteCard` issues `DELETE …/cards/:id` and invalidates
`{ type: 'Card', id: boardId }`. There is no archive anything.

## Decisions

### D-1 — archive sits beside delete, in both places a card is acted on

**Decision.** **Archive** is added next to **Delete**; delete is not moved, not demoted and not
replaced. Both appear in both places a card can be acted on:

| Where                                 | What it shows   |
| ------------------------------------- | --------------- |
| the card's dot menu on the board      | Archive, Delete |
| the card detail dialog (`CardDialog`) | Archive, Delete |

One action in one place and not the other is how a user learns a feature exists and then cannot
find it again. The dot menu is where a card is dismissed in passing; the dialog is where someone
has the card open and decides it is finished. Both are the moment.

Deleting is currently the only way to clear a finished card, so people delete what they would
rather keep. Archive does not take that away — it gives the common case somewhere else to go,
and delete keeps meaning exactly what it means today.

**Delete keeps its confirmation and its `with_children` option; archive has neither.** Archive
is reversible, so a dialog asking whether you are sure is friction charged for nothing, and
D-6 settles the children question without asking.

### D-2 — the archive is a route under the project, not a global page

**Decision.** `/projects/:id/archive`, added to the `projects` plugin's `routes` array —
one line in `src/plugins/projects/index.tsx`, no new plugin.

An archived card belongs to a project's workspace, not to the application: two projects have
two archives, and there is no view in which they should be mixed. A route rather than a modal
because the list is unbounded, it has to survive a reload, and a URL is what makes "look at what
we archived last month" shareable.

**Rejected.** A new `DashboardPlugin`. The contract would take one — `id`, `name`, `nav`,
`routes` — but a plugin is how a new _area_ is added, and this is the projects area seen from a
different angle. A plugin would also put "Archive" in the sidebar with no project selected,
which means nothing.

**Rejected.** A tab beside the board tabs. `BoardTabs` switches between boards inside one
workspace; the archive is not a board, and putting it there would make it a drop target for
drag-and-drop, which D-4 deliberately avoids.

### D-3 — restoring must ask where to

**Decision.** Restore is never a bare button. It opens a small form with a board and a column,
defaulting to where the card was archived from when that column still exists, and to the board's
first column when it does not.

This is the decision that would otherwise be discovered as a bug. Columns are deleted; boards
are deleted; a card archived in _Review_ three months ago may have no _Review_ to go back to.
A restore that guesses silently drops the card somewhere surprising, and a restore that fails
with "column not found" blames the user for something the board did while the card was away.

It follows that an archived card must carry its origin — board id and column id at the moment it
was archived — which § What this needs from the server records as a requirement rather than a
convenience.

### D-4 — no drag-and-drop, in either direction

**Decision.** Archiving is a menu action; restoring is a form. Neither is a drag.

The board already has drag-and-drop for moving cards between columns, and extending it to a
route that is not on screen at the same time is a different problem — a drag needs both ends
visible. The reverse, dragging out of the board into a sidebar, hides a destructive-looking
action behind a gesture with no confirmation.

_ponytail: menu and form. If people archive dozens of cards at a time, multi-select with one
Archive action is the next step, and it is additive._

### D-5 — two lists change on every archive, and both must be invalidated

**Decision.** A new RTK Query tag `{ type: 'Archive', id: projectId }`. Both mutations
invalidate the board's `{ type: 'Card', id: boardId }` **and** the project's `Archive` tag.

Miss the first and the board keeps rendering a card that is gone; miss the second and the
archive view is missing the card that just arrived, or still shows the one just restored. Both
are the kind of staleness that looks like data loss.

The live socket carries `workspaceChanged(projectId)` already, and the app refetches on it, so a
change made from the CLI or MCP should reach both views without a new event kind — confirm that
against `packages/state/src/live/` before relying on it.

### D-6 — archiving a card archives its children, and restoring brings them back

**Decision.** Archiving a parent archives its whole subtree. Restoring it brings back exactly
the cards that went with it, and nothing else.

A sub-task without its parent is orphaned work: it stays on the board describing a step of
something no longer there. Leaving children behind would make archiving a parent the fastest way
to create cards nobody can place.

Two consequences, and both are requirements rather than details:

**The archive remembers the operation, not just the card.** Each archived record carries the id
of the archive that produced it. Restoring a parent restores that batch — so a child archived on
its own three weeks earlier is not dragged back by a parent archived today, and a child archived
_with_ the parent is not left behind. Without this, restore has to guess from the parent/child
links, which are themselves archived history and say nothing about when.

**Every card in the batch keeps its own origin.** The restore form (D-3) asks for the parent's
board and column. Each child returns to the column _it_ was archived from; when that column is
gone, it falls back to the destination chosen for the parent, which is a place the user just
confirmed exists. So one question restores a subtree, and no card lands somewhere nobody picked.

**Rejected.** A `with_children` flag mirroring delete. Delete has one because deleting a parent
and keeping orphans loses the structure forever, so the caller must choose. Archiving loses
nothing — the links are kept as history — so the choice has no stakes and a flag would only
create a way to make the board wrong.

### D-7 — the list is flat, newest first, and unpaginated until it hurts

**Decision.** Sorted by archived date descending, showing title, key, the board and column it
came from, and when. No filters, no search, no pagination.

A personal board's archive is tens of cards, not thousands. `Page` already exists in
`DashboardAPI` for when that stops being true, so the upgrade is a parameter and not a redesign.
An empty state says archiving is where finished cards go, because a feature nobody can find is
a feature nobody uses.

## Every surface, not only the web

Archiving is a workspace operation, so it belongs to the command protocol every surface already
goes through (`BoardCommands`), not to the HTTP layer. Once it is there, the three clients are
three thin call sites:

| Surface | What it gets                                                                                              |
| ------- | --------------------------------------------------------------------------------------------------------- |
| web     | this note — the view, the menu entries, the restore form                                                  |
| CLI     | `dashboard card archive <project> <card>`, `dashboard card restore <project> <card> [--board] [--column]` |
| MCP     | `archive_card` and `restore_card`, taking `project, board, card` like `delete_card`                       |

Every one of them is **project-scoped**, like every other command in this repository —
`dashboard project show <name|id>`, `dashboard ai ticket <project> …`, and every MCP tool taking
`project` first. A card id is unique inside a workspace, not across a machine, so a command
without a project has nothing to resolve it against.

The MCP half has prior art: kanban-rs's own server exposes archive and restore tools, so the
names and shapes are not a fresh invention, and an agent that clears a finished board is exactly
the case archiving exists for.

Their tasks belong to the backend note, not here — `web/docs/` is frontend only. This note
records the requirement so the backend note is not written for one client.

## What this needs from the daemon

Not decided here — this is the contract, and the backend note decides how to satisfy it.

| Endpoint                                   | Purpose                                            |
| ------------------------------------------ | -------------------------------------------------- |
| `GET …/kanban/v1/archive`                  | the project's archived cards, newest first         |
| `POST …/boards/:board/cards/:card/archive` | move a card and its subtree off the board          |
| `POST …/archive/:card/restore`             | put the batch back, body `{ board_id, column_id }` |

An archived record must carry, at minimum:

| Field                   | Needed by     | Why                                                            |
| ----------------------- | ------------- | -------------------------------------------------------------- |
| `project_id`            | every surface | which project and board this card belongs to, without a lookup |
| `board_id`, `column_id` | D-3           | where to put it back, and what to fall back from               |
| `archived_at`           | D-7           | newest first                                                   |
| `archive_id`            | D-6           | which children came with this parent                           |

`project_id` looks redundant inside the file — the archive lives in the project's own workspace,
so the container already says it. It is not redundant anywhere the record leaves that container:
a CLI printing JSON, an MCP tool answering an agent, a log line. A record that only means
something in its container is the kind that gets copied out and loses its meaning, and the fix
costs one field.

Open on the backend side, and the reason it needs its own note: `archived_cards` is an
unmodelled passthrough today, kanban-rs writes that section too, and both stores have to keep
round-tripping it. Whether archiving means "modelled at last" or "appended to the passthrough"
changes the on-disk contract in [`PRD.md`](../../../docs/PRD.md) § Data contract.

## Not in this note

- **Where archived cards live** — the backend note.
- **Archived boards.** `archived_boards` is the same kind of unmodelled section; a board is not
  a card and the destination question does not apply to it.
- **Retention.** Nothing expires an archived card. If that is ever wanted it is a server policy.
- **The board's drag-and-drop** — untouched, see D-4.

## Tasks

- **T-18 (S)** `Archive` tag, and the three endpoints in `packages/state/src/api/kanbanApi.ts`.
  — WEB · blocked by the backend note
- **T-19 (S)** Archive beside Delete in the card's dot menu **and** in `CardDialog`; delete
  unchanged. — WEB · T-18
- **T-20 (M)** `/projects/:id/archive`: the route, the list, the empty state. — WEB · T-18
- **T-21 (M)** Restore with a board and column picker, defaulting to the origin when it still
  exists; a subtree restores as one batch. — WEB · T-20
- **T-22 (S)** Tests: both lists refetch after archive and after restore; restoring to a deleted
  column falls back rather than failing; archiving a parent removes its children from the board
  and restoring it brings back that batch only. — WEB · T-21
