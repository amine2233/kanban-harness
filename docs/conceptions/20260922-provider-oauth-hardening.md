# Provider OAuth hardening

OAuth in this project means **Hugging Face**: an authorization-code flow with PKCE, an access
token that expires, and a refresh token. Vendors that authenticate with an API key are out of
scope here — they have no callback, no expiry and no refresh, so none of the decisions below
apply to them.

The flow shipped and works. Three of the assumptions it was designed against did not survive
contact with the code: the callback is no longer guaranteed to be loopback, the per-request
refresh mechanism it relied on was never built, and nothing records that signing out is local
only. This note decides those corrections (T-37, T-39, T-40) plus the storage race that parallel
sign-ins expose (T-42), and records why T-41 stays deferred.

[`provider-sign-in.md`](20260921-provider-sign-in.md) decides the flow itself — PKCE, `state`, session
TTL, the credential store — and stays authoritative for it.

## Why now

`provider-sign-in.md` states the callback is `http://127.0.0.1:5175/api/auth/callback` and that
"the server binds loopback, which is what the vendors expect for a local app". The
implementation builds the redirect URI from the request's `Host` header instead
(`AIConfigController.beginSignIn`), and the loopback premise no longer holds:
`dashboard serve --hostname 0.0.0.0` is supported and has two `mise` tasks behind it
(`serve:lan`, `dev:lan`), while `Configure.swift` installs only CORS and error middleware — the
API has no authentication.

This is **robustness, not a vulnerability**. Hugging Face validates `redirect_uri` against the
registered OAuth app, so a forged `Host` yields a URL the vendor rejects. It is still worth
fixing: it hardcodes `http://`, which is wrong behind TLS, and the containment depends entirely
on a vendor-side check rather than on anything this code does. A future vendor that accepts a
free-form callback would make the same code exploitable with no change on our side.

Verified by reading `AIConfigController.swift`, `Configure.swift` and `ServeCommand.swift`; not
reproduced against a live vendor.

## Decisions

### T-37 — the callback URL is configuration, not a request header

**Decision.** Add `publicURL: URL?` to `ServerConfig`, beside `corsOrigins` — the same kind of
transport-level setting, owned by the same type, set by a `dashboard serve --public-url` flag
and `MVP_DASHBOARD_PUBLIC_URL`. `beginSignIn` builds the callback from it. When it is unset, the
`Host` header is accepted only if its host is loopback (`127.0.0.1`, `localhost`, `::1`);
anything else is a `400`. This also removes the hardcoded `http://` scheme.

**Rejected.** Probing whether something is listening on the web port and using it as the
callback: "a socket is open on 5173" does not mean "my Vite dev server with its `/api` proxy is
there", the answer can change between `begin` and the callback, and in production there is no
such port at all. It would derive a security-relevant URL from an ambient, spoofable signal —
the same class of mistake as trusting `Host`, which is what this decision exists to remove. The
value is known up front in every mode, so it is configuration, not a discovery problem.

Also rejected: validating `Host` against an allowlist: under `--hostname 0.0.0.0` the legitimate
host is the machine's LAN address, which is not known when the config is written, so the
allowlist cannot be populated. Also rejected: requiring `--public-url` unconditionally, which
breaks the default loopback flow that works today and buys nothing.

**How it is set in each mode.** The callback must be the origin the browser actually has the
app at. Every mode already knows that value without discovering it:

| Mode                           | Callback origin             | How it is known                                                                          |
| ------------------------------ | --------------------------- | ---------------------------------------------------------------------------------------- |
| `mise run dev` (Vite)          | `http://127.0.0.1:5173`     | `scripts/dev.sh` holds `WEB_PORT` when it launches the backend; it passes `--public-url` |
| `dashboard serve --static-dir` | the server's own origin     | default path — the server serves the app, so the loopback `Host` is right                |
| CLI, server running            | the server's origin         | the route decides, as today                                                              |
| CLI, no server                 | `http://127.0.0.1:<random>` | the temporary server supplies its own callback, untouched                                |

Vite proxies `/api` to `127.0.0.1:5175` (`web/vite.config`), so a callback on `5173` reaches the
server through the proxy and the relative redirect lands back on `5173`, where the app is. This
is also what fixes the missing dev confirmation banner.

**Where it is resolved, and why that matters.** There are two callback producers, and only the
first has the bug:

| Producer                                                                     | How it gets a callback                                                                         | Affected |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | -------- |
| `AIConfigController.beginSignIn` (web, and the CLI when a server is running) | from the request `Host` header                                                                 | yes      |
| `AILoginCommand.viaTemporaryServer` (CLI, no server)                         | builds `http://127.0.0.1:<random>/api/auth/callback` and calls `SignInCommands.begin` directly | no       |

The CLI has no server of its own. With one running it goes through the route, and
`RemoteSignInCommands.begin` sends `body: Empty?.none` — the `callback` argument it accepts is
**discarded**, so the server's derivation is the only one that counts. With no server it starts
Vapor on port `0` and supplies its own loopback callback, bypassing the controller entirely.

So the resolution must happen **at the HTTP boundary, in the controller**.
`ProviderSignInService.begin` keeps taking an explicit `callback` and must never override it —
putting the `publicURL` logic in the service would replace the temporary server's random-port
callback with a configured URL nothing is listening on, breaking sign-in precisely for the user
who has no server running. That is the trap this decision exists to avoid.

**What it means for the web sign-in.** The browser flow already exists and is tested
(`AIProvidersCard.tsx`, `AIProvidersCard.test.tsx`): the settings card opens the authorization
URL with `window.open(url, '_blank')`, and after the exchange `completeSignIn` answers
`req.redirect(to: "/settings?signed_in=<id>")`. That redirect is **relative**, so it resolves
against whatever origin served the callback, and `signInLanding()` only shows the confirmation
because it reads `signed_in` from `window.location.search` in the tab that landed there.

`publicURL` therefore decides where the user ends up after signing in, not just what the vendor
calls back. That fixes the definition rather than complicating it: `publicURL` is **the origin a
browser reaches this dashboard at**, which is exactly the origin the post-sign-in redirect must
resolve against. A `publicURL` pointing somewhere the browser cannot load the app would leave
the user on a blank page with a credential correctly stored — the failure is cosmetic but
confusing, so it belongs in the flag's documentation.

**Touches.** `DashboardServer` (`ServerConfig`, `AIConfigController`), `DashboardCLI`
(`ServeCommand`), `scripts/dev.sh` (one flag on the `serve` line). Not `DashboardOAuth` and not `DashboardAI`: the flow is unchanged, only the
URL handed to it, and `SignInCommands.begin` keeps its signature.

**Verified by.** Route tests: a non-loopback `Host` with no `publicURL` returns `400`; a
loopback `Host` still produces a callback; `publicURL` wins when both are present; and
`completeSignIn` redirects under `publicURL` when one is set. Plus the case the table makes
load-bearing: with `publicURL` set, `AILoginCommand`'s temporary server still signs in against
its own random-port loopback callback. `mise run backend:test`.

### T-42 — parallel sign-ins must not lose a credential

The loopback listener side is already right and needs no change: `viaTemporaryServer` binds
`127.0.0.1` on port `0`, so the OS picks a free port and two concurrent runs cannot collide, and
it calls `asyncShutdown()` on both the success and the error path. Within one process,
`SignInSessions` is an actor keyed by `state`, so any number of flows can be in flight at once.

The storage underneath is not. `FileCredentialStore.set` reads `credentials.json`, mutates the
dictionary and writes it back, with no lock anywhere in `Sources/`. Two sign-ins finishing in
different processes — two CLI logins, or a CLI login beside the running server — interleave as
read/read/write/write and one credential is silently dropped. `AtomicFile.write` compounds it by
using a fixed temp path (`path + ".tmp"`) that both writers share, and `Data.write(to:)` without
`.atomic` can interleave inside it.

**Decision.** Two changes, both in the storage layer, neither touching the flow:

1. `AtomicFile.write` writes to a unique temp path (pid plus a random suffix) before the
   `rename`, so concurrent writers never share a staging file.
2. `FileCredentialStore` takes an advisory `flock` on the credentials file for the whole
   read-modify-write, so the last writer merges rather than overwrites.

**Rejected.** Making `FileCredentialStore` an actor: it serialises one process, and the case
that actually loses data is two processes. Also rejected: one file per provider, which removes
the merge but changes the on-disk format that `provider-sign-in.md` fixed and that users already
have.

**Touches.** `DashboardPersistence` (`AtomicFile`), `DashboardPersistenceConfig`
(`FileCredentialStore`). No change to `DashboardOAuth`, `DashboardAI` or the CLI.

**Verified by.** A test that two concurrent writers storing different provider ids both survive,
and that the temp file is gone afterwards. `mise run backend:test` plus
`mise run backend:test:linux` — `flock` behaviour is the kind of thing that differs between
Darwin and Linux.

### T-39 — expiry belongs to the domain value, renewal to the AI layer

Hugging Face is the only kind whose credential expires, so this decision has one vendor to
satisfy. Two placements, both plausible; the cost decides.

**(a) Refresh inside the credential read path** (`ConfigFileAIConfigStore.load`). Every consumer
becomes correct with no discipline required. But `DashboardPersistenceConfig` must not own
secrets ([`ARCHITECTURE.md`](../ARCHITECTURE.md)), and renewing needs the provider registry and
an outbound HTTP call, so a persistence type would acquire an AI-layer dependency and network
I/O. **Rejected on the layering rule**, not on taste.

**(b) Surface `expiresAt` on `AIProviderConfig`** (domain, pure, no I/O) and keep the renewal in
`ProviderSignInService.refreshed`. A consumer holding a config can see the secret is stale, so
skipping the refresh becomes visible at the call site instead of silently producing a 401.
**Chosen.**

`provider-sign-in.md` designed a third option — per-request refresh through an `@autoclosure`
key on `OpenAILanguageModel`. That autoclosure does not exist in this codebase (no occurrence of
`autoclosure` under `Sources/`), which is why `refreshed()` is hand-called from
`AssistantService`, today the only drafting path. This note supersedes that mechanism.

**Touches.** `DashboardDomain` (`AIProviderConfig`), `DashboardPersistenceConfig` (populate
`expiresAt` from the credential while resolving the key), `DashboardAI`
(`ProviderSignInService`).

**Verified by.** A config resolved from an expiring credential carries `expiresAt`; a config
resolved from an environment variable or a pasted key carries none; `AIConfigDTO` still emits
neither the secret nor the expiry. `mise run backend:test`.

### T-40 — `signOut` is local by design, and should say so

**Decision.** A comment on `ProviderSignInService.signOut` recording that it deletes the stored
credential and does not revoke at the vendor, with the consequence (the Hugging Face access
token stays valid until it expires) and the reason (a failed remote revoke must not block a
local sign-out).

**Rejected.** Calling Hugging Face's revocation endpoint: it adds a network failure mode to a
local delete, for one vendor, with no way to succeed offline.

**Touches.** `DashboardAI` only. Comment, no behaviour change.

**Verified by.** Nothing. This is deliberately a comment-only patch with no check; its content
is a claim about what the code does _not_ do, which no test can assert.

## Order of work

1. **T-42** — a correctness fix in storage, independent of everything else, and the only one
   that can lose user data. It also makes T-39 testable without a race in the fixture.
2. **T-37** — changes an externally visible contract (the redirect URI), so it should settle
   before anything builds on it.
3. **T-39** — behaviour change, touches the domain.
4. **T-40** — a comment; it can ride with any of the above.

No refactor-before-behaviour pairing applies here: none of the four moves code without changing
it.

## Deferred

**T-41 — `OAuthVendor` descriptor.** A declarative vendor record (authorize and token URL,
scopes, whether an app registration is required) so a new vendor is a constant rather than a
module. Not now: Hugging Face is the only vendor with a sign-in, so the descriptor would have
exactly one instance. An abstraction with one implementation hides no variation, it only guesses
at it.

**Trigger.** The second vendor with a real OAuth flow (Groq, Mistral, Together, GitHub Models).
At one instance the shape is a guess; at two the differences are evidence.

## Not in this note

- **The sign-in flow itself** — `provider-sign-in.md` remains authoritative for PKCE, `state`,
  session TTL and the credential store.
- **T-38, the `registerOpenAICompatible` dedupe** — it is about duplicated provider
  registration, not about OAuth, and it touches vendors that never sign in. It needs its own
  note, or it can go straight to a series from its entry in the note that owns it.
- **API-key vendors** — no callback, no expiry, no refresh; nothing here applies to them.
- **`KeychainCredentialStore`** — T-26, already scoped in `provider-sign-in.md` §1.
- **Web client changes** — the settings sign-in already exists and needs no code change: it
  reads `signed_in` from the URL it lands on, whatever that origin is. Only the server decides
  that origin. Should the landing tab need to talk back to the opener, that is client work and
  belongs in `web/docs/TASKS.md`.
- **CORS and `--public-url` interaction** — `--cors-origin` governs XHR; the callback is a
  top-level navigation and is not subject to it.
- **`RemoteSignInCommands.begin` accepting a `callback` it discards** — a misleading signature,
  not a defect: the server owns the callback by design.

## Open questions

- **Must a non-loopback `publicURL` be HTTPS?** Hugging Face registers a redirect URI on the
  OAuth app and several providers refuse a plaintext non-loopback redirect. If so, T-37 should
  reject an `http://` `publicURL` whose host is not loopback rather than accept a URL the vendor
  will later refuse. Needs checking against Hugging Face's app settings before T-37 is cut into
  patches; it changes one validation branch, not the design.
- **In Vite dev the confirmation banner never appears.** The app is served on `5173` while the
  API and the callback are on `5175`, so the new tab lands on `5175/settings`, which serves no
  frontend unless `--static-dir` is set. Pre-existing, independent of T-37, and arguably the
  first thing `publicURL` should be pointed at in a dev setup. Worth confirming before deciding
  whether it needs its own task.
- **`dashboard ai providers login <id>` reports success without signing in when a credential
  already exists.** Both poll conditions ask whether a credential is present, not whether this
  sign-in completed — `waitUntil { …hasAPIKey == true }` (`AILoginCommand:43`) and
  `waitUntil { credentials.get(id) != nil }` (`:62`). Re-authenticating an expired Hugging Face
  token is exactly when this is run. A defect in the existing flow rather than part of the
  hardening, so it needs its own card before being designed here.

## Tasks

- **T-37 (S)** Build the redirect URI from `publicURL`; with none set, accept the `Host` header
  only when it is loopback, otherwise `400`. — SRV-09 · —
- **T-39 (M)** Surface `expiresAt` on `AIProviderConfig` so a stale secret is visible at the call
  site; renewal stays in `ProviderSignInService.refreshed`. — SRV-09 · —
- **T-40 (S)** Record in `ProviderSignInService.signOut` that it does not revoke at the vendor.
  — SRV-09 · —
- **T-41 (M)** `OAuthVendor` descriptor so a vendor is data, not a module. — SRV-09 · T-38 ·
  deferred: one conforming vendor today, OpenRouter deliberately does not fit; revisit at the
  second standard-OAuth vendor
- **T-42 (M)** Make concurrent credential writes safe: a unique temp path in `AtomicFile.write`,
  an advisory `flock` around `FileCredentialStore`'s read-modify-write. Two sign-ins finishing in
  different processes lose one credential today. — SRV-09 · —
