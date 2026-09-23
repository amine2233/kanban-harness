# Web App Requirements

_Frontend only. Product scope and the backend live in [`docs/`](../../docs/PRD.md)._

## What it is

The browser surface of the dashboard: where a human looks at a board, edits cards by direct
manipulation, and watches an AI write a ticket before deciding to keep it. One React app,
three library packages, no server of its own.

## Who it is for

The single human user of [`docs/PRD.md`](../../docs/PRD.md#users). Not the agent: agents use
MCP, not the browser. The app assumes one machine, one account, no login.

## What it adds over the CLI

- Seeing the board — columns, WIP pressure, sub-tasks under their parent, colours per family.
- Direct manipulation: drag a card, reorder a column, tick a checklist item in a description.
- Watching a draft arrive token by token, with its stages, cost and raw output, and cancelling
  it without a trace.
- Settings that are discoverable instead of remembered.

## Scope

In: project list and project page, boards, columns, cards, sub-tasks, markdown descriptions,
AI drafting and its activity panel, cost display, the three settings areas, live refresh,
theme.

Out: anything the server owns (files, storage kind semantics, providers' secrets), multi-user
concerns, offline editing, mobile-specific layouts, internationalisation.

## Requirements

The ids are the `WEB-*` rows of [`docs/PRD.md`](../../docs/PRD.md#functional-requirements) —
same numbering, restated here as the client's own contract.

| ID     | The app must                                                                | Priority |
| ------ | --------------------------------------------------------------------------- | -------- |
| WEB-01 | Register a project from the sidebar: path, optional name, storage kind      | MUST     |
| WEB-02 | Manage boards from tabs, delete behind a confirmation                       | MUST     |
| WEB-03 | Manage columns inline, including WIP limit and default status               | MUST     |
| WEB-04 | Edit every card field in one dialog, delete behind a confirmation           | MUST     |
| WEB-05 | Move a card by drag and drop and by a keyboard-reachable control            | MUST     |
| WEB-06 | Show sub-tasks under their parent with a done count; a moved child keeps it | MUST     |
| WEB-07 | Draft with AI in the new-card dialog, filling fields as the model types     | MUST     |
| WEB-08 | Show stages, provider, timings, tokens, cost, errors and raw output         | MUST     |
| WEB-09 | Create nothing before the user asks; parent and sub-tasks in one request    | MUST     |
| WEB-10 | Show a drafted card's cost on the board and in the dialog                   | MUST     |
| WEB-11 | Switch storage kind and unregister a project from the project page          | MUST     |
| WEB-12 | Offer three settings areas: this browser, the server, the AI providers      | MUST     |
| WEB-13 | Render markdown descriptions with checklists that write back when ticked    | MUST     |
| WEB-14 | Refresh on any change from any surface, without a reload                    | MUST     |
| WEB-15 | Read server state only through the store; no component calls the network    | MUST     |
| WEB-16 | Register a new app area as a plugin (nav, routes, optional sidebar)         | SHOULD   |
| WEB-17 | Reconnect fast and show whether it is live, reconnecting or stale           | SHOULD   |
| WEB-18 | Let the user pick a drafting agent and edit agents in settings              | MAY      |

## The app must never

- Hold server state the store did not fetch, beyond per-browser preferences
  (`localStorage`, key `mvp-dashboard.settings`).
- Touch a project file, or assume anything about how the server stores it.
- Call `fetch` from a component, or hand-write a URL outside `@mvp/state`.
- Write to a board without a user action — a draft is a proposal until Create.
- Block the UI on the network: every request has a visible pending and error state.

## Success criteria

1. A new project can be registered, filled and deleted without touching a terminal.
2. A card dragged to another column stays there after a reload.
3. A change made from the CLI shows up in an open tab within a second, no reload.
4. Cancelling a draft leaves no card and no request in flight.
5. Every mouse action on a card has a keyboard-reachable equivalent.
6. With the server stopped, the app says so and recovers on its own when it returns.
7. `pnpm check`-equivalent (`pnpm format:check`, `lint`, `typecheck`, `test`, `build`) passes.

> TODO(owner): no accessibility level and no performance budget is stated anywhere
> ([`docs/PRD.md`](../../docs/PRD.md#open-questions)); criterion 5 is the only one written.
