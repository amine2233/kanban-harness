# The config file references a secret; it never contains one

The companion to [`oauth-token-store.md`](20260924-oauth-token-store.md), and the other half of the split
that note opens with. A token the dashboard obtained has to be kept. An API key the operator
supplied does not — it should be referenced, and live somewhere the config file can point at.

That makes `config.yaml` safe to commit, to paste into an issue, and to copy between machines,
by construction rather than by remembering.

## Today

`ConfigFileAIConfigStore` resolves a provider's key in this order: the environment variable
`MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY`, then the credential store, then `api_key:` in the
config file. The environment path deliberately never persists — `storeSecret` returns early when
the value equals the environment's.

That was right when the process holding it was the command you had just typed, in the shell that
exported it. The daemon changed it. The daemon inherits the environment of **whichever command
happened to start it** and then outlives every one of them, so an exported key lasts exactly as
long as that process. Export it, run a command, let the daemon be replaced from a different
shell, and the key is gone with no explanation — the provider just reports itself unconfigured.
[`daemon.md`](../../website/docs/daemon.md) already documents people arriving at this from the
other side: _an environment variable seems ignored_.

## Decisions

### D-1 — `${VAR}`, resolved when the file is read

**Decision.** Any string value in `config.yaml` may be written `${VAR}`.

```yaml
ai:
  providers:
    claude:
      api_key: ${ANTHROPIC_API_KEY}
```

**`${VAR}` only — never bare `$VAR`.** A bare name has no terminator, so `$HOME_DIR` cannot be
told from `$HOME` followed by `_DIR`, and every literal `$` inside a value becomes a guess.
Secrets contain `$`. A key mangled by a parsing rule fails as _unauthorized_ at the vendor, which
sends whoever hits it to a status page instead of to their own config. `$$` escapes a literal
`$`.

It is also the syntax [`T-20`](../TASKS.md) already plans for `mcp.json` in Claude Code's format,
so this is one resolver with two consumers rather than two dialects.

### D-2 — resolution order, and failing loudly

**Decision.** The process environment first, then `home/.env`. An unresolved `${VAR}` is an error
naming the variable and the file that referenced it.

Never the empty string. A provider whose key resolved to `""` reports `has_api_key: true`, sends
the request, and returns the vendor's authentication error — the most expensive possible way to
learn about a typo.

### D-3 — resolution happens on read, and only on read

**Decision.** Every write path — `ConfigFileAIConfigStore.save`, `dashboard ai providers add` —
round-trips the literal `${VAR}` back to the file untouched.

This is the one way the feature can do harm. A save that writes the resolved value back turns a
referencing config into a leaking one, silently, in a file the user now believes is safe to
commit. It is worth more than a passing mention because the bug is invisible: everything keeps
working, and the only symptom is a secret in a diff.

### D-4 — `home/.env`, because the daemon outlives the shell

**Decision.** The daemon reads `home/.env` — `KEY=value` per line, `#` comments, mode `0600` —
and its values resolve `${VAR}` when the process environment has none.

A file in the home belongs to the home, the way `credentials.sqlite` and `daemon.port` already
do, so every daemon that owns that home reads the same one. That is the fix for the symptom
above: the secret stops depending on which shell happened to spawn the daemon.

It is read per request, as `config.yaml` already is, so correcting a key takes effect without
`dashboard daemon stop`.

`.env` is already this project's word for this — `.env.dist` is in the repository and `mise.toml`
loads `.env.local` — so nothing new is being named. What is new is that the **daemon** reads one,
rather than depending on what a developer's shell happened to carry.

### D-5 — only the home's `.env`, never a project's

**Decision.** Exactly one `.env` is read: the one in the resolved home. Never the working
directory, never a registered project's folder, never a parent walk.

The home can be repository-local — `./.kanban-harness/` is the documented way to give a
repository its own projects and daemon. So "a `.env` next to the code" and "the home's `.env`"
can be the same file, and the difference has to come from the path the home resolved to, not from
proximity to the command.

Without this rule, cloning a repository that happens to contain a `.env` would let it substitute
a provider credential — pointing a provider at an attacker's base URL with an attacker's key, or
capturing what gets sent. OpenClaw blocks workspace `.env` files from supplying provider
credentials for exactly this reason, and it is the one part of their design that is not
already implied by ours.

A home that is repository-local is still trusted: the user created `.kanban-harness/` themselves.
What is not trusted is any `.env` that merely happens to be nearby.

### D-6 — no template engine

**Decision.** One function in `DashboardPersistenceConfig`, beside the store that calls it: scan
for `${`, read to `}`, look the name up, substitute or throw.

Stencil, Mustache and the rest are template _languages_ — `{{ }}`, `{% for %}`, filters,
inheritance. The requirement is one substitution rule with one failure mode. A language adds a
dependency, a parser surface where a stray `{%` breaks a file people hand-edit, and an invitation
to put logic in configuration. It also cannot produce `${VAR}` without being configured or
preprocessed, so it would not even save writing the scan.

**Check before writing it.** `ConfigFileDatabaseConfigStore` already layers an
`EnvironmentVariablesProvider` over the file through swift-configuration. That is _key-level_
override — `MVP_DASHBOARD_DATABASE_THREAD_POOL_SIZE` replacing `database.thread_pool_size` — and
not interpolation inside a value. If swift-configuration turns out to have value expansion, use
it and delete this decision.

_ponytail: no `${VAR:-default}`, no nesting, no recursion. A secret has no sensible default, and
the other two are how a substitution rule becomes a language._

### D-7 — what a resolved value may never do

**Decision.** [R-23](../RULES.md) covers logging. Two more, because referencing invites them:

- the API keeps reporting `has_api_key`, never the value, resolved or literal.
- an error about an unresolvable `${VAR}` names the **variable** — never a partial value, never
  the contents of `.env`.

### D-8 — `MVP_DASHBOARD_AI_PROVIDERS_<ID>_API_KEY` becomes redundant, and is deprecated

**Decision.** The dedicated variable keeps working, warns once when it is used, and is removed in
a later version. `${VAR}` replaces it.

It exists to let a key arrive from the environment without being written down. `${VAR}` resolves
from the process environment first (D-2), so the same deployment writes
`api_key: ${ANTHROPIC_API_KEY}` once in `config.yaml` and exports the variable — same property,
same CI ergonomics, one mechanism instead of two.

Keeping both is what makes a support question start with "which one won?". After this note a key
can arrive five ways: `${VAR}` from the environment, `${VAR}` from `home/.env`, the dedicated
variable, the credential store, and a literal `api_key:`. Five is already too many, and the
dedicated variable is the one that now buys nothing.

**Deprecated, not deleted.** A working setup must not break on upgrade: the variable is still
read, and using it logs one `warning` naming the provider and the `${VAR}` line that replaces it.
Removal is a separate decision, after a release that warned.

**Rejected.** Removing it in the same change. It is the only secret path some CI configurations
have, and an upgrade that silently stops reading a key looks exactly like a vendor outage.

### D-9 — a home inside a repository gets a `.gitignore`

**Decision.** When the home is created, write a `.gitignore` containing `*` into it. The daemon
refuses to read a `home/.env` that `git check-ignore` says is **not** ignored while the home sits
inside a work tree, and says why.

`./.kanban-harness/` is the documented way to give a repository its own projects and daemon
([`cli-as-source-of-truth.md`](20260923-cli-as-source-of-truth.md)), which puts the home **inside the work
tree**. Everything this note and
[`oauth-token-store.md`](20260924-oauth-token-store.md) put in the home — `.env`, `credentials.json`, the
sealed database, the key that opens it — then sits where `git add -A` can reach it.

The asymmetry is what makes it worth a decision rather than a README line: a leaked `.env` is
rotated by changing a key, while a key committed to a repository's history cannot be revoked at
all — it can only be replaced, which invalidates every token it sealed. A one-line file written
at creation removes the whole class, and costs nothing to someone whose home is in
`~/.config`.

**Rejected.** Refusing a repository-local home. It is a deliberate, documented feature, and the
user who created `.kanban-harness/` meant it.

_ponytail: `.gitignore` at creation plus the one check on `.env`. If people still commit a key,
the next step is refusing to start in a tracked home — but that fails hard on a setup that was
working yesterday, so it wants evidence first._

## Implementation

**[1/4] The resolver.** Scan for `${`, read to `}`, substitute from a `[String: String]`, throw
naming the variable. `$$` escapes.
_Check: a unit test for substitution, `$$`, an unresolved name, a value containing a literal `$`,
and a `${` with no closing brace._

**[2/4] The read path resolves; the write path proves it does not.**
`ConfigFileAIConfigStore.load` resolves, `save` round-trips the literal. D-3 is the reason this
patch exists, so its test is the point of it.
_Check: load a config with `api_key: ${K}`, change an unrelated field, save, assert the file still
reads `${K}` and not the resolved value._

**[3/4] `home/.env`.** Parsed on read: `KEY=value`, `#` comments, no `export`, no command
substitution, no shell semantics. `0600` when the tool writes one. Process environment wins. Only
the resolved home's file, per D-5.
_Check: a CLI test that puts a key only in `home/.env`, starts a daemon from a shell without it,
replaces the daemon, and asserts the provider still resolves — the symptom this note opened with.
Plus one asserting a `.env` in the working directory is ignored when the home is elsewhere._

**[4/4] The `.gitignore` and the deprecation warning,** D-9 and D-8. A `.gitignore` containing
`*` written when the home is created; one `warning` when the deprecated variable supplies a key,
naming the provider and the `${VAR}` line that replaces it.
_Check: a test creating a home inside a work tree and asserting `git check-ignore` reports the
home's files as ignored; and one asserting the deprecated variable still resolves and warns._

## Not in this note

- **OAuth tokens** — [`oauth-token-store.md`](20260924-oauth-token-store.md). They cannot be referenced;
  the dashboard is what obtains them.
- **`mcp.json`** — `T-20` uses the same resolver; the file and its trust prompt are its own task.
- **Encrypting `config.yaml`.** It holds no secret once this lands; that is the point.

## Open questions

- **Does `.env` deserve a command?** `dashboard secrets set KEY` writing `home/.env` at `0600`
  avoids a hand-made file with the wrong mode, but it is another surface, and the file is two
  lines of text.
- **Reporting where a value came from.** `dashboard ai providers list` could show `env`, `.env`,
  or `config` per provider. Useful exactly once — while someone is debugging why a key vanished —
  which may be often enough.

## Tasks

Each one is a patch in § Implementation above; this list is what
`scripts/next-tasks.sh` reads.

- **T-62 (S)** The `${VAR}` resolver: scan, substitute, throw naming the variable. — SRV-09 · —
- **T-63 (M)** The read path resolves and the write path round-trips the literal — the patch
  that can leak, so its test is the point of it. — SRV-09 · T-62
- **T-64 (S)** `home/.env`, and only the home's. — SRV-09 · T-62
- **T-65 (S)** The home's `.gitignore` and the deprecation warning on the dedicated variable.
  — SRV-09 · T-64
