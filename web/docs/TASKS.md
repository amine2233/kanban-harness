# Web App Backlog

_Frontend only. Backend tasks: [`docs/TASKS.md`](../../docs/TASKS.md)._

From the `SHOULD` / `MAY` `WEB-*` requirements of [`docs/PRD.md`](../../docs/PRD.md) and the
client half of the design notes. Size: `S` under a day, `M` a few days, `L` more.

Format: **T-nn (size)** task — requirement · blocked by.

## Live connection

The client half of `docs/conceptions/live-connection.md`; the server half is `docs/TASKS.md`
T-01…T-09. Order from the note.

- **T-01 (S)** Watchdog in `liveMiddleware`: no frame for twice the heartbeat interval means
  the socket is dead — close it and reconnect at once. — WEB-17 · server T-01
- **T-02 (S)** Invalidate every tag on `hello`, so the screen is right after any gap, replayed
  or not. Today `hello` invalidates nothing. — WEB-17 · —
- **T-03 (S)** Fast-path reconnect on `online`, `visibilitychange` → visible, `focus`, and on a
  fulfilled query while the status is closed; add jitter to the backoff. — WEB-17 · —
- **T-04 (M)** Handle `resume` / `resync`: send the last `{epoch, seq}` on open, invalidate
  everything on `resync`, invalidate only their tags for replayed events. — WEB-17 · server T-03
- **T-05 (S)** Status states in the shell: `reconnecting` and `stale` next to the existing live
  / connected / offline, so "server down" reads differently from "catching up". — WEB-17 · T-01
- **T-06 (S)** Open the socket directly on the backend port in development instead of through
  the Vite proxy. — WEB-17 · server T-08
- **T-07 (S)** Tests for all of it with the existing fake socket and fake timers. — WEB-17 · T-04

## AI agents

Step 3 of `docs/conceptions/ai-agents.md`; the backend must land first.

- **T-08 (S)** Agent select next to Provider in `DraftWithAI`, defaulting to the configured
  default agent. — WEB-18 · backend T-16
- **T-09 (M)** Settings → AI agents: list with the default badge, editor (name, description,
  knobs, markdown body with Write/Preview), new, duplicate, delete. — WEB-18 · backend T-16
- **T-10 (S)** _Try it_: draft a fixed sample idea with the selected agent, streamed into the
  existing activity panel, creating nothing. — WEB-18 · T-09
- **T-11 (S)** Show the agent in the activity panel summary and in the card's cost details. —
  WEB-18 · backend T-14

## Cost

- **T-12 (M)** Show a card's cost history rather than the single creation entry, once the
  server records one. — open question · backend T-27
- **T-13 (S)** Project total on the project page. — open question · backend T-28

## Quality

- **T-14 (M)** Accessibility pass: keyboard path for every board action, focus management in
  dialogs, visible focus, announced live-region updates. Needs a target level first. — R-14 ·
  T-16
- **T-15 (M)** Behaviour under a large board (hundreds of cards): measure before optimising,
  then memoise or virtualise. Needs a budget first. — open question · T-17

## Documentation debt

- **T-16 (S)** Fix `website/docs/web/architecture.md`: it says events are not processed, gives
  wrong dashboard-home paths, names different default columns than the README, and links a file
  that does not exist. — DOC-03 · —

## Decisions needed

- **T-17 (S)** State an accessibility target (WCAG level) and a performance budget for the
  board, or declare both out of scope.
