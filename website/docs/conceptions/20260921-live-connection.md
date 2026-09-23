---
slug: /conceptions/live-connection
title: Live connection
---

:::note Design note
Why the live socket drops and an architecture, modelled on Herdr, that survives sleeps, proxies, restarts and crashes. Source: `docs/conceptions/20260921-live-connection.md`.
:::

# A stable live connection

Why the `/api/events` socket keeps dropping, and an architecture — modelled on
[Herdr](https://herdr.dev)'s persistent server + snapshot/subscribe protocol — that stays
correct through sleeps, proxies, backend restarts and crashes.

## Today

- Server: `GET /api/events` upgrades to a WebSocket; each mutation is fanned out from
  `ChangeBroadcaster` as `{kind, project_id?}`; a client that falls behind loses the oldest
  events (`bufferingNewest(64)`). No ping, no sequence numbers, no replay.
- Web: one socket owned by `liveMiddleware`; a frame invalidates RTK Query tags; on close it
  reconnects with exponential backoff (1 s → 30 s). `hello` invalidates nothing.
- Dev: the socket goes through Vite's proxy to a backend that is restarted on every rebuild.

### Why it "crashes"

| Symptom                                   | Cause                                                                                                       |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| status stuck on _open_, no updates arrive | half-open socket after sleep / proxy reset: **no heartbeat**, so nobody notices until a send fails          |
| after a reconnect the board is stale      | events emitted during the gap are lost and the reconnect **does not resync**                                |
| 30 s of _closed_ after waking the laptop  | backoff has no fast path: **no reconnect on `online` / tab visible**                                        |
| drops on every backend rebuild in dev     | the server process is the connection; a restart kills every socket, and Vite's WS proxy adds its own resets |
| the server itself dies                    | any crash (e.g. a failed migration assertion) takes the socket with it; **nothing restarts the process**    |

None of these is one bug. The connection needs a protocol that assumes disconnection is
normal, and a process that assumes crashes are normal.

## What Herdr does that we should copy

From its socket API (newline-delimited JSON over a Unix socket):

- **A persistent server** clients attach to and detach from; the server, not the client, owns
  the state. `herdr status server` reports the socket path and protocol compatibility.
- **Bootstrap = subscribe, then snapshot, then replay**: _"first open `events.subscribe`
  … buffer that stream while calling `session.snapshot`, install the snapshot, then apply the
  buffered events in order"_ — and _"call `session.snapshot` again after reconnecting"_.
  Reconnecting is a re-bootstrap, never a resume-in-place.
- **Explicit `ping`**, request ids for multiplexing, error `{code, message}`.
- **Forward compatibility**: _"ignore unknown fields and handle unsupported methods as normal
  errors"_; the server advertises the protocol it speaks.

Our equivalent: RTK Query caches are the "snapshot" (a refetch), change events are the
stream. So a re-bootstrap is: **(re)open the stream, then refetch everything the UI shows** —
any event that lands during the refetch only triggers another refetch, which is idempotent.

## Design

Three layers; each one is useful alone and they build on each other.

### Layer 1 — a protocol that survives disconnection

Frames stay JSON text, one object per message; unknown kinds and fields are ignored.

```text
server → client  hello      {kind, protocol: 1, epoch, seq, heartbeat_ms}
server → client  event      {kind, seq, project_id?}            (existing kinds)
server → client  heartbeat  {kind}                               every heartbeat_ms
server → client  resync     {kind, reason}                       "you missed events I no longer have"
client → server  resume     {kind, epoch, seq}                   first frame after open, optional
```

- **`epoch`** identifies one server process (a UUID minted at start); **`seq`** is a counter
  within it. Together they name a position in the stream.
- The server keeps the last N events (1024) in a ring — `ChangeLog`, replacing
  `ChangeBroadcaster`'s fire-and-forget. A `resume {epoch, seq}` that falls inside the ring is
  answered by replaying the missing events; a different epoch or a position that fell out of
  the ring is answered with `resync`, and the client refetches everything.
- **Heartbeat**: the server sends `heartbeat` (and a WebSocket ping) every 15 s; the client
  runs a watchdog — no frame for `2 × heartbeat_ms` means the socket is dead: close it and
  reconnect immediately. This is the fix for "stuck on open".
- **Bootstrap rule (Herdr's)**: on every `hello`, the client invalidates every tag
  (`Project, Board, Column, Card, Settings, AIConfig`). It costs a handful of GETs and
  guarantees the screen is right after any gap, replayed or not. Replay then only saves the
  refetch when nothing changed.

### Layer 2 — a client that reconnects fast and quietly

`liveMiddleware` becomes a small state machine: `idle → connecting → open → (dead|closed) → backoff → connecting`.

- Backoff `1 s · 2 s · 4 s … 30 s` **with jitter**, reset on `hello`.
- **Fast paths** that skip the backoff: `window` `online`, `visibilitychange` → visible,
  `focus`, and a successful HTTP call (RTK Query `fulfilled` while status is `closed`).
- The status shown in the top bar gains _reconnecting_ and _stale_ (open, but the last
  bootstrap failed) so a user can tell "the server is down" from "I am catching up".
- Tests: fake socket + fake timers already exist in `liveMiddleware.test.ts`; add the watchdog,
  the resume/replay path, the `resync` path, and the fast-path triggers.

### Layer 3 — a server that is always there (Herdr's persistent server)

The socket can only be as stable as the process behind it.

- **Supervise it.** `scripts/dev.sh` restarts the backend when it exits non-zero (with a
  short delay and a log line), instead of dying with it. In production, document a
  `launchd` plist (macOS) and a `systemd` unit (Linux) with `KeepAlive` / `Restart=on-failure`,
  and add `dashboard server status` (pid, uptime, epoch, socket clients) like `herdr status server`.
- **Crash less.** The server must never assert on data it reads: migration failures, corrupt
  files and provider errors become HTTP errors, not traps (the `ai_cost` duplicate-column crash
  was exactly this class). A crash-only test suite: start the server, break a project file,
  hit every route.
- **Dev without the Vite WS proxy.** Let the app open the socket **directly** to the backend
  port (`ws://127.0.0.1:5175/api/events`) while HTTP keeps going through the proxy; WebSockets
  are not subject to CORS, the server binds loopback. One less hop, no proxy resets. Backend
  restarts still drop the socket, but layer 1+2 turn that into a sub-second re-bootstrap.

## Alternative worth considering: SSE instead of WebSocket

The stream is one-directional, and the browser's `EventSource` already implements most of
layer 1+2: automatic reconnection, `Last-Event-ID` on reconnect (our `seq`), a server-set
`retry:` delay, and comment lines as heartbeats. The server side already speaks SSE for AI
drafting (`SSEParser`, `AssistantFrame`). Trade-off: no client → server frames (we have none),
and HTTP/1.1's per-origin connection limit (one tab uses one). If the WebSocket keeps
misbehaving after layer 1, switching the transport to SSE removes the custom reconnect code
altogether and is the smaller implementation.

## Order of work

1. **Heartbeat + watchdog + invalidate-all on `hello` + fast-path reconnect** (web +
   `EventsController`): fixes the three visible symptoms; no protocol change beyond two new
   frame kinds. Half a day.
2. **`epoch`/`seq` + `ChangeLog` ring + `resume`/`resync`**: precise recovery, fewer refetches.
3. **Supervision**: `dev.sh` restart loop, `dashboard server status`, launchd/systemd docs.
4. **Direct socket in dev** (skip the Vite WS proxy).
5. Re-evaluate SSE once 1–2 are in: if the WebSocket path still needs babysitting, replace it.

## Tests

- Server: `ChangeLog` replay/resync boundaries; heartbeat cadence; `resume` from a stale epoch.
- Web: watchdog closes a silent socket; `hello` invalidates all tags; `resync` invalidates all
  tags; replayed events invalidate only their tags; `online`/visible reconnects at once; jitter
  bounded.
- Process: `dev.sh` restarts a backend that exits 1; `dashboard server status` reports the epoch.

## Not in scope

- Multi-server or shared event log across processes (one server per machine).
- Client → server commands over the socket — HTTP stays the command channel.
