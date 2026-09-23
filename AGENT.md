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
  └─ docs/conceptions/ the RFC — the decision   provider-sign-in.md
       └─ docs/series/ the decomposition        [1/N] … [N/N]
            └─ git     the patches              one commit each
                 └─ docs/TASKS.md   what is left, and in what order
```

Entering in the middle is the usual mistake. No conception note behind the work → write the
note, or ask. A patch is not the place to decide a design.

Three rules this file owns; everything else is a link.

1. **The agent proposes, the human signs.** No commit of a diff nobody read.
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
| [`docs/TASKS.md`](docs/TASKS.md)               | picking up work                                |
| [`docs/DEBUG.md`](docs/DEBUG.md)               | a port is held or a server will not start      |

Target-by-target ownership is the table in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — it is the only copy.

## Commands

`mise tasks` lists them all. The ones that gate a change:

| Command                       | Gates                                                                |
| ----------------------------- | -------------------------------------------------------------------- |
| `mise run backend:test`       | `swift test`                                                         |
| `mise run backend:test:linux` | the same in `swift:6.3.3-noble` — where this package actually breaks |
| `mise run check`              | everything CI runs, both areas                                       |

## Rules broken most often

- A rule outside `DashboardDomain`, or a target importing upwards — [R-01, R-02](docs/RULES.md).
- A route that talks to a store instead of a command-protocol method — [R-03](docs/RULES.md).
- Branching on `StorageKind` outside `WorkspaceStores.factory` — [R-04](docs/RULES.md).
- A service created inline instead of in `DashboardRuntime.register` — [R-06](docs/RULES.md).
- `Date()`, `UUID()` or the environment instead of `@Dependency` — [R-07](docs/RULES.md).
- A new store that does not run `StoreContract` — [R-17](docs/RULES.md).

## Picking up work

`docs/TASKS.md` carries `· blocked by`, which is a dependency graph.
`scripts/next-tasks.sh` sorts it into a build order and fails loudly on a cycle.

## Before you finish

`mise run check` green. For backend-only work, `mise run backend:test` **and**
`mise run backend:test:linux` — macOS stays green while Linux fails, so it is always found
late. Prettier covers `docs/` and `.github/workflows/`, so a hand-written Markdown file fails
the web job.
