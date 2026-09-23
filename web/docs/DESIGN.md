# Web App Design Decisions

_Frontend only. Backend decisions: [`docs/DESIGN.md`](../../docs/DESIGN.md)._

Decisions already paid for. Structure: [`ARCHITECTURE.md`](ARCHITECTURE.md). Rules:
[`RULES.md`](RULES.md).

## D-01 Redux is the frontend's source of truth

Components read the store and never the network; every request goes through an RTK Query
endpoint in `@mvp/state`. **Not:** per-component `fetch` with local state, which makes two
screens showing the same card disagree. **Cost:** a new endpoint is a file in `state`, not a
hook next to the component.

## D-02 Caches are the snapshot, events are the stream

A change event carries no data: it names what went stale and the affected query refetches.
**Not:** patching the cache from the event payload, which duplicates the server's shapes in the
client. **Cost:** one extra GET per change, which is idempotent and makes every tab correct.

## D-03 Mutations invalidate, they do not update optimistically

A move sends the `PATCH` and waits for the refetch. **Not:** optimistic cache writes, which
need a rollback path for every domain rule (WIP limits, status rules) that only the server
knows. **Cost:** a visible round trip on a drag.

## D-04 The base URL is resolved per request

`baseApi`'s base query reads `settings.serverUrl` on each call. **Not:** a URL captured at
store creation, which needs a reload after a settings change. **Cost:** a selector call per
request.

## D-05 One socket, owned by middleware

`liveMiddleware` holds the only WebSocket, turns frames into actions and invalidates tags.
**Not:** a hook or a context provider, which would open a socket per mount and lose frames
between route changes. **Cost:** the socket lives outside React and is started explicitly by
`App`.

## D-06 Plugins instead of a central router

A feature exports `nav`, `routes` and an optional `sidebar`; `plugins.ts` lists them. **Not:**
one router file every feature edits. **Cost:** an indirection, and duplicate ids fail at
startup rather than at compile time.

## D-07 Three packages with layering enforced by the linter

`kanban-model` has no React, `design-system` has no store, `state` has no components.
**Not:** folders with a convention, which decay. **Cost:** an ESLint block per layer and one
`tsconfig.json` per package.

## D-08 Only the design system knows the CSS classes

`hk-*` and `ds-*` live behind components; the app composes components. **Not:** utility classes
sprinkled through the plugins, which pins every screen to purple3. **Cost:** a new visual needs
a design-system change, not a local one.

## D-09 A pure module next to every component

`cardForm.ts`, `boardIndex.ts`, `dragAndDrop.ts`, `tracker.ts`, `origins.ts` hold the
decisions; the `.tsx` renders them. **Not:** logic in hooks, which can only be tested by
rendering. **Cost:** two files instead of one.

## D-10 Drafting is a stream with a visible account

The assistant slice reduces SSE frames into stages, a partial draft, usage and a result; the
activity panel shows all of it, including the raw output. **Not:** a spinner and a final
result, which hides what was sent, what it cost and why it failed. **Cost:** a state machine
and a panel to maintain.

## D-11 A draft is a proposal

`partial` fills the form; nothing is created until the user submits, and a parent with its
sub-tasks is one request. **Not:** creating a card and editing it in place.

## D-12 Browser settings in `localStorage`, server settings on the server

The server URL and the theme are per-browser and persisted by a store subscription; everything
else is fetched. **Not:** a synced profile, which the product has no account to hang on.
**Cost:** two settings areas in one page, visibly labelled.

## D-13 Tests stub the server, not the store

`stubApi()` from `@mvp/state/testing` answers `METHOD /api/path` and can emit SSE frames, so a
UI test exercises the real store, the real endpoints and the real middleware. **Not:** mocking
hooks or preloading state, which passes while the wiring is broken. **Cost:** a fixture per
route touched.

## D-14 Remount on project change instead of resetting state

`ProjectPage` keys `KanbanBoard` by project id, and `BoardColumns` by `projectId-boardId`.
**Not:** an effect that clears state, which runs after a render with the wrong data (fixed in
`9462643`). **Cost:** losing transient UI state on a project switch — which is the intent.
