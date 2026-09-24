---
slug: /conceptions/oauth-token-store
title: oauth token store
---

There are two kinds of secret here and they want opposite things.

An **API key** is supplied by the operator. The dashboard should never persist it — it should
reference it. That is
[`config-secret-references.md`](config-secret-references), and this note does not touch it.

An **OAuth token** is different. Nobody can put it in a `.env`, because the dashboard is what
obtains it: the vendor hands back an access token and a refresh token at the end of the browser
flow, and if the dashboard does not keep them the user signs in again on every restart. There is
no "reference it instead" option. It has to be stored, so the only question is how.

[`provider-sign-in.md`](provider-sign-in) § 1 answered that with `credentials.json` at `0600`,
before the daemon existed. This note replaces that answer for tokens.

## Decisions

### D-1 — tokens live in their own database, not in the registry

**Decision.** `home/credentials.sqlite`, created `0600`, with its own migration list and its own
`SQLiteDatabase.credentials(path:)` factory beside the existing `registry` and `workspace` ones.

Not `projects.sqlite`. That file is the registry, and a registry is something you copy — to move
a setup to another machine, to back up, to hand to someone debugging. Every one of those becomes
a secret leak the moment tokens live in it. A separate file keeps "copy my projects" and "copy my
credentials" separate decisions, which is the same reason `credentials.json` was never part of
`config.yaml`.

Fluent and FluentSQLiteDriver are already dependencies, and the daemon is the only process that
opens a database ([`cli-as-source-of-truth.md`](https://github.com/amine2233/kanban-harness/blob/main/docs/conceptions/20260923-cli-as-source-of-truth.md) D-1), so there is no
second writer to coordinate with.

**Rejected.** Whole-database encryption with SQLCipher. It is a C dependency, which the backend
CI image (`swift:6.4.0-noble`) would have to grow, and it moves the problem rather than solving
it — the passphrase still has to live somewhere.

### D-2 — each token is sealed on its own, with AES-GCM

**Decision.** The row holds `provider_id`, a sealed blob, an `expires_at`, and timestamps. The
blob is `AES.GCM.seal` over the JSON of `Credential` — so the access token, the refresh token and
the authoritative expiry are all inside it.

swift-crypto is already a dependency; `DashboardOAuth/PKCE.swift` uses it for SHA256, so
`AES.GCM` costs nothing new.

Three properties the implementation has to get right, because each has a silent failure mode:

- **A fresh nonce per write.** `AES.GCM.seal` generates one when not given one; never reuse a
  nonce with the same key, and never store one alongside as if it were a salt. Store
  `sealed.combined` — nonce, ciphertext and tag together — and let the library take them apart.
- **The provider id is authenticated, not just stored.** Seal with
  `authenticating: Data(providerId.utf8)`, so a row copied from one provider to another fails to
  open instead of silently handing Anthropic's token to OpenRouter.
- **`expires_at` in the clear is a hint, never a fact.** It is there so the refresh sweep can
  find candidates without decrypting every row, and it is outside the sealed blob, so nothing
  authenticates it. Select on it; decide on the copy inside the blob.

### D-3 — the key is random, generated once, and never derived from the machine

**Decision.** 256 bits from `SymmetricKey(size: .bits256)` on first use, written to
`home/credentials.key` with `O_CREAT|O_EXCL` and mode `0600`.

`O_EXCL` because two daemons racing to create it would otherwise leave one of them writing rows
the other cannot read — the same reasoning as the `daemon.lock` exclusive create.

**Never derived from machine identity.** `/etc/machine-id`, the hardware UUID, the hostname —
none of these are secrets. Anyone who can read the database can read them too, so a key derived
from them is an encoding, not encryption, and it would be one that _looks_ like protection in a
security review.

What this buys, stated honestly so nobody over-trusts it: the key sits beside the data, so
someone who can read the home can read both. It is not a defence against a stolen home
directory. It **is** a defence against the leaks that actually happen — a token in the output of
`cat`, in a `grep`, on a screenshare, in a support bundle, in a backup that skipped a dotfile.
Those are the common ones, and today every one of them exposes a live token.

**Rejected.** A passphrase the user types. The daemon starts unattended, from a command that is
itself unattended; there is nobody to ask.

**Rejected for now.** Keeping the key in the platform keystore instead of a file — the macOS
Keychain, Secret Service, `systemd-creds`. That is the version that survives a stolen disk, and
it is one ACL prompt for the whole store rather than one per provider. It is deferred, not
dismissed: `KeyProvider` is a protocol with one implementation today, so the file is replaceable
without touching the store. See [`provider-sign-in.md`](provider-sign-in) `T-26` and the
prompt problem the daemon creates — it is spawned onto `/dev/null`, and the ACL binds to a binary
that `swift build` replaces.

### D-4 — losing the key means signing in again, and says so

**Decision.** A row that will not open is not a crash and not a silent empty result. The store
reports the provider as signed out and logs one `warning` naming it; `dashboard ai providers
list` shows it as needing sign-in.

This is a real path, not a theoretical one: deleting `credentials.key`, restoring a home from a
backup that missed it, or copying a home between machines all produce it. The recovery — sign in
again — is cheap, and the only way to make it un-cheap is to hide it behind a stack trace.

The key file is excluded from anything the tool itself exports, and from the repository when the
home lives inside one — see [`config-secret-references.md`](config-secret-references) D-9. A
key committed to a repository's history cannot be revoked, only replaced, and replacing it
invalidates every token it sealed.

### D-5 — refresh stays where it is

**Decision.** Renewal keeps happening through `ProviderSignInService.refreshed()`, at read, as
`T-39` decides. The store gains the ability to _find_ expiring rows, and that is all it gains.

Moving tokens into a database invites a background sweep — a task that wakes up and renews
everything about to expire. That needs a schedule, a failure policy, a backoff, and a reason to
retry a vendor that just said no; and the read path has to keep working anyway for the case where
the sweep has not run yet. Do the read path, keep the query, and let a sweep be a decision with
evidence behind it.

### D-6 — the move off `credentials.json` is a move, not a copy

**Decision.** On first start with the new store: read every credential from the file store, write
it to the database, verify it reads back, then delete the file. In that order, and abandon the
whole migration if any step fails — leaving the file intact.

A half-migration that has deleted the file and cannot open the rows has destroyed the only copy
of a refresh token, and a refresh token is the thing that cannot be recreated without the user.

## Implementation

**[1/5] `SQLiteDatabase.credentials(path:)` and the model.** A factory beside `registry` and
`workspace` — `registry` hardcodes `FluentProjectStore.migrations`, so the new one carries its
own. One model: `provider_id` as the primary key, `sealed` blob, `expires_at`, `created_at`,
`updated_at`.
_Check: the migration runs on an empty home and is idempotent._

**[2/5] `CredentialKey`.** `SymmetricKey` load-or-create at `home/credentials.key`,
`O_CREAT|O_EXCL`, `0600`. Behind a `KeyProvider` protocol so D-3's deferred keystore has
somewhere to land.
_Check: two concurrent creates yield one key; a second call returns the same bytes._

**[3/5] `SQLiteCredentialStore`.** `CredentialStore` conformance — seal on `set`, open on `get`,
`authenticating:` the provider id. It passes the existing `StoreContract.verify`, so the contract
test is the check and no new one is written.
_Check: `StoreContract.verify`; plus a test that a row moved between provider ids fails to open,
and one that two writes of the same credential produce different ciphertext._

**[4/5] Selected in `DashboardRuntime.register`,** where every other backend choice is made.
_Check: the runtime test asserts the registered store is the SQLite one and the file is `0600`._

**[5/5] Migration from `credentials.json`,** D-6, in the read-write-verify-delete order.
_Check: a test with a populated `credentials.json` asserting every credential is readable from the
database and the file is gone; and one where the write fails, asserting the file survives._

## Not in this note

- **API keys** — [`config-secret-references.md`](config-secret-references).
- **The sign-in flow** — `provider-sign-in.md` § 2 and § 3.
- **Revocation.** Signing out drops the local token and leaves the grant alive at the vendor
  (`T-40`); where it was stored changes nothing.
- **Renewal policy** — `T-39`.

## Open questions

- **Key rotation.** Re-encrypting every row is straightforward; what is not decided is what would
  trigger it, and whether a rotation that fails halfway is recoverable without a second key slot.
- **The keystore upgrade.** D-3 defers it. The thing to watch is whether people hit the stolen-home
  case at all, or only ever the accidental-exposure ones the file key already covers.

## Tasks

Each one is a patch in § Implementation above; this list is what
`scripts/next-tasks.sh` reads.

- **T-57 (S)** `SQLiteDatabase.credentials(path:)` and the row model. — SRV-09 · —
- **T-58 (S)** `CredentialKey`: load-or-create at `home/credentials.key`, `O_CREAT|O_EXCL`,
  behind a `KeyProvider`. — SRV-09 · —
- **T-59 (M)** `SQLiteCredentialStore`, sealing with the provider id authenticated; it passes
  `StoreContract`. — SRV-09 · T-57 · T-58
- **T-60 (S)** Selected in `DashboardRuntime.register`. — SRV-09 · T-59
- **T-61 (M)** Migration off `credentials.json`, read-write-verify-delete, abandoned whole on
  any failure. — SRV-09 · T-60
