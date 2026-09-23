# Backend — the Swift package

_Server, `dashboard` CLI and MCP over one domain. Other areas: [`web/`](web/AGENT.md) for the
React app, [`website/`](website/AGENT.md) for the published site._

This directory owns the data and the rules. The web app renders what `/api` returns and decides
nothing; a rule that lives anywhere but `DashboardDomain` grows a second version within a month.

The process section below is repo-wide — it governs `web/` and `website/` too.

## The chain

A decision is made once, written down, then cut into patches implemented by hand.

```
docs/PRD.md            the requirement          SRV-17
  └─ docs/conceptions/ the RFC — the decision   20260921-provider-sign-in.md
       └─ its § Tasks  what is left             T-26 (M) … — SRV-09 · blocked by
            └─ docs/series/ the decomposition   [1/N] … [N/N]
                 └─ git    the patches          one commit each
```

Entering in the middle is the usual mistake. No conception note behind the work → write the
note, or ask. A patch is not the place to decide a design.

Three rules this file owns; everything else is a link.

1. **The agent proposes, the human signs.** No commit of a diff nobody read. A commit whose
   code an assistant wrote ends with `Assisted-by: LLM <model>` — never `Co-Authored-By:`, and
   never a `Signed-off-by` from the assistant. An assistant is a tool; the person who merges is
   the author of the change, however much of it was typed by something else. The distinction is
   the kernel's, in
   [`Documentation/process/coding-assistants.rst`](https://docs.kernel.org/process/coding-assistants.html):
   only a person can certify where a patch came from.
2. **Green at every commit**, not only the last — the bar is [`docs/MEMORY.md`](docs/MEMORY.md)
   § _What counts as verified_.
3. **One fact, one home.** A rule, command or trap written in two files disagrees within a
   month. Link instead of copying — including into this file.

How to cut a series — one change per patch, refactor before behaviour, each patch standing
alone and naming its check — is specified in
[`.claude/commands/agent-os/plan-code.md`](.claude/commands/agent-os/plan-code.md) and is not
repeated here. Run it with `/agent-os:plan-code <note | id | sentence>`.

## Read first

| File                                           | Open it when                                   |
| ---------------------------------------------- | ---------------------------------------------- |
| [`docs/PRD.md`](docs/PRD.md)                   | deciding whether something belongs here at all |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | you need the targets, the layering or the flow |
| [`docs/DESIGN.md`](docs/DESIGN.md)             | you are about to do something a different way  |
| [`docs/RULES.md`](docs/RULES.md)               | before writing code — it is short              |
| [`docs/MEMORY.md`](docs/MEMORY.md)             | something behaves in a way that makes no sense |
| [`docs/conceptions/`](docs/conceptions/)       | the design is not settled yet                  |
| [`docs/conceptions/`](docs/conceptions/)       | picking up work — each note carries its tasks  |
| [`docs/DEBUG.md`](docs/DEBUG.md)               | a port is held or a server will not start      |

Target-by-target ownership is the table in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — it is the only copy.

## Commands

`mise tasks` lists them all. The ones that gate a change:

| Command                       | Gates                                                                |
| ----------------------------- | -------------------------------------------------------------------- |
| `mise run backend:test`       | `swift test`                                                         |
| `mise run backend:test:linux` | the same in `swift:6.4.0-noble` — where this package actually breaks |
| `mise run check`              | everything CI runs, both areas                                       |

## Rules broken most often

- A rule outside `DashboardDomain`, or a target importing upwards — [R-01, R-02](docs/RULES.md).
- A route that talks to a store instead of a command-protocol method — [R-03](docs/RULES.md).
- Branching on `StorageKind` outside `WorkspaceStores.factory` — [R-04](docs/RULES.md).
- A service created inline instead of in `DashboardRuntime.register` — [R-06](docs/RULES.md).
- `Date()`, `UUID()` or the environment instead of `@Dependency` — [R-07](docs/RULES.md).
- A new store that does not run `StoreContract` — [R-17](docs/RULES.md).

## Picking up work

Every conception note ends with a `## Tasks` section listing what is left to implement it:

```
- **T-nn (S|M|L)** what to do. — PRD id · blocked by
```

`· blocked by` is a dependency graph across all the notes; `scripts/next-tasks.sh` sorts it into
a build order and fails loudly on a cycle. A task with no note behind it is not a task yet — it
is a card on the board, or a question in [`docs/PRD.md`](docs/PRD.md) § _Open questions_. There
is no separate backlog file: an index every branch edits is where merge conflicts come from.

## Before you finish

`mise run check` green. For backend-only work, `mise run backend:test` **and**
`mise run backend:test:linux` — macOS stays green while Linux fails, so it is always found
late. Prettier covers `docs/` and `.github/workflows/`, so a hand-written Markdown file fails
the web job.
