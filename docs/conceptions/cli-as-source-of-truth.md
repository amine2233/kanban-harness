# The CLI owns the data; every other surface is a client

Today the CLI, the server and MCP are siblings: each builds its own container, opens the same
files and runs its own `ChangeBroadcaster`. This note makes the CLI the single owner and turns
the server and MCP into clients of it over a local socket.

[`live-connection.md`](live-connection.md) decides the **browser ↔ server** socket — heartbeat,
resync, backoff — and stays authoritative for it. This note decides the **daemon ↔ interface**
socket, which is a different hop.

## Why now

Two processes already break, and the reasons are structural rather than incidental.

| Observed                                    | Cause                                                                                                                                         |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| MCP + server hangs the backend              | two processes open one SQLite file → `SQLITE_BUSY` → sqlite-nio retries forever holding a thread-pool thread ([`MEMORY.md`](../MEMORY.md) §2) |
| an MCP or CLI change never shows in the web | `ChangeBroadcaster()` is built per container (`DashboardRuntime.register`), so each process fans out only to itself                           |

Commit `1920634` fixed the first failure _inside_ one process by pinning one event loop per
file. Nothing guards it across processes: `flock`, `O_EXLOCK`, lockfile and pidfile have no
occurrence under `Sources/`.

`Mode` (`DashboardCLI/Runtime.swift`) is the current answer, and it cannot work. It resolves
`isReachable()` **once**, at process start, and never again. That is fine for a command that
lives 40 ms and wrong for `dashboard mcp`, which lives for an editor session: started before the
server, it takes `.local`, holds the file, and the server then becomes the second writer.

The data model is already right and this note does not touch it. `projects.sqlite`,
`settings.json`, `config.yaml` and `credentials.json` are global under `home`
(`RuntimeConfig`); each project owns `kanban.json` or `kanban.sqlite`
(`WorkspaceStores.factory`); `AIConfig` carries no `projectId`, so AI is shared across projects
as intended. What changes is **which process holds them open**.

## Decisions

### D-1 — exactly one process opens a database

**Decision.** The `dashboard` daemon is the only process that opens `projects.sqlite`, the
config and credential files, and any project's `kanban.*`. `DashboardRuntime.register` is called
there and nowhere else. The server, MCP and one-shot CLI commands hold no store.

This is the whole point: it is an invariant about file handles, not a statement about authority.
Once it holds, the `SQLITE_BUSY` deadlock cannot be reached, because a second opener does not
exist.

**Rejected.** An advisory `flock` per process, leaving the current shape intact: it converts the
hang into a clear error, which is an improvement, but it still leaves MCP and the server unable
to run together — the thing that is actually wanted.

### D-2 — a command that finds no daemon starts one

**Decision.** Every surface connects to the socket first. On `ENOENT` or a refused connection it
spawns the daemon, waits for the socket, and retries once. A stale socket file with nothing
behind it is unlinked and treated as absent.

`Mode`, `GlobalOptions.forcedMode`, `--local` and `--remote` are **deleted**. There is no second
wiring path to choose between, so there is nothing to force.

**Rejected.** Requiring an explicit `dashboard daemon start`: predictable, but it makes the first
run of every command fail for a reason the user did not cause.

### D-3 — one socket, one broadcaster

**Decision.** The daemon listens on a unix socket under `home`. The server, MCP and one-shot
commands all connect to that one path. The daemon holds the single `ChangeBroadcaster`; a
mutation from any client fans out to every subscriber.

That is what makes an MCP edit appear in the browser: the event does not cross a process
boundary any more, it originates inside the only process that has one.

**Rejected.** A socket per interface, which is permitted by the requirement and buys nothing:
the interfaces do not differ in protocol, and the sync they need comes from sharing a
broadcaster, not from sharing a path. One path, one accept loop.
_ponytail: one socket; split it if an interface ever needs a different framing._

**Transport.** Loopback TCP on a dedicated daemon port (`MVP_DASHBOARD_DAEMON_PORT`, default
`5174`), not a unix socket. `DashboardClient` is built on `URLSession`, which cannot dial a unix
domain socket on either platform, so a unix socket would mean porting the whole client transport
to AsyncHTTPClient. That buys file-permission access control on a hop where the alternative is
no worse than today — `dashboard serve` already binds TCP with no authentication — so it is not
worth the rewrite. The web server keeps its own port for the browser, and `--hostname 0.0.0.0`
continues to describe **it**, never the daemon, which stays on `127.0.0.1`.

_ponytail: fixed port, like the existing `5175`. A port file plus `:0` removes the collision if
one ever shows up._

### D-4 — an interface cannot crash the daemon

**Decision.** `dashboard serve` is a separate process that connects to the socket and bridges to
the browser. Each client connection is independent: closing or crashing one drops that
connection's subscribers and nothing else. The daemon never exits because a client went away.

The browser keeps talking HTTP and WebSocket to the server exactly as today — `/api/events`
stays where it is, with the behaviour `live-connection.md` specifies. The server stops being a
data owner and becomes a translator between two sockets.

### D-6 — a daemon from another build is not an owner to use

**Decision.** `/api/health` reports the build the answering process runs, and a command accepts
a daemon only when that build is its own. A mismatch goes down the path a missing daemon already
takes: ask the owner to let go, spawn, retry. Upgrading the binary therefore needs no ceremony,
and the two processes never share a home.

The build is the declared version plus the executable's modification time, read once at process
start. A rebuild during development is what actually produces the skew, and it does not bump a
version string; a daemon that read the value lazily would report the binary that replaced its own
and the mismatch would vanish exactly when it matters.

A daemon older than this field answers without one, which reads as a mismatch — which is the
right answer, since an old daemon is what the check is looking for.

**Rejected.** A protocol version negotiated per connection. The transport is HTTP and the client
is `URLSession`: there is no handshake to hang it on, and `/api/health` is already the liveness
probe every surface calls before doing anything else.

_ponytail: the client evicts on any difference. Comparing a wire-compatibility number instead
would keep a daemon alive across harmless rebuilds, if respawning ever costs too much._

### D-5 — CascadeKit is the container; a plugin is a registration that may not happen

**Decision.** Everything with a lifetime resolves through the CascadeKit `Container` under a
`ServiceKey`; ambient values stay on `@Dependency`. "Plugin" means a module decides whether to
`register` itself — **AI providers only**, since several vendor targets already exist and differ.

**Not built.** A plugin manifest, discovery, or toggles for storage backends and interfaces.
CascadeKit's public API is `Storage`, `DependencyKey`/`DependencyValues`/`@Dependency`,
`Container`, `ServiceKey`, `Factory` and `Lock` — there is no plugin primitive to lean on, so
any of that is ours to build and maintain. One toggle with one real case is enough.

## Order of work

1. **D-1 + D-3** — stand the daemon up with the socket and the broadcaster, with `serve` still
   able to run the old way. Nothing observable changes yet.
2. **D-4** — point `serve` at the socket and delete its container.
3. **D-2** — point MCP and the one-shot commands at the socket; delete `Mode` and its flags.
   This is the patch that fixes the reported crash.
4. **D-5** — provider registration, once the container is the only wiring left.

## Not in this note

- **The browser socket** — `live-connection.md` owns heartbeat, resync and backoff.
- **The wire protocol on the daemon socket** — framing, versioning and what happens when a
  client is older than the daemon. It needs its own note before step 1 is cut into patches.
- **The on-disk formats** — unchanged; `PRD.md` §data-contract stays the contract.
- **Provider OAuth** — [`provider-oauth-hardening.md`](provider-oauth-hardening.md) is
  independent, except that its `publicURL` keeps describing the web server, not the daemon.

## Open questions

- **Daemon lifetime.** Does it exit after an idle period, or live until the machine restarts? An
  idle timeout keeps a laptop clean but makes the next command pay a spawn.
- **Spawn races.** Two commands starting at once both find no socket and both spawn. An
  exclusive create on a lock file under `home` is the usual fix; confirm it before step 1.
