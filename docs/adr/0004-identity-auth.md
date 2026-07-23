# ADR-0004 — Identity & Auth at Launch

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Each public request is authenticated. The `identity` context owns users, sessions
and auth. Constraints: no external dependency on the 1-core 4 GB VPS, no homebrew
cryptography, secure-by-design. We have only two actor classes at Launch — `player`
and `system` (the feed/scheduler adapters running as trusted in-process callers).

## Decision

- **In-house `identity` context** built only on vetted Go libraries:
  - Password hashing: **Argon2id** (`crypto/argon2` recommend params; m=64 MiB, t=3, p=1).
  - Signing: **Ed25519** (`crypto/ed25519`), keys on disk, rotated; never serialized to logs.
  - JWT: `golang-jwt/jwt/v5`, short-lived access tokens (10 min).
- **Refresh-token rotation with reuse-detection.** Refresh tokens stored **hashed**
  (SHA-256) in `identity.refresh_tokens` keyed by `(user_id, device_id)`. On rotation,
  the previous token is invalidated; reuse of an invalidated token revokes the entire
  session family (reuse-detection).
- **One active session per (user, device).** Older device sessions are revoked.
  Players may list and revoke their sessions.
- **Two signing keys, two token audiences:**
  - `player` key — signs user access tokens, never visible to internal adapters.
  - `system` key — signs tokens for `feed`, `scheduler`, `game.ResolveMatch` etc.
    Internal adapters mint a `system` token with their own short-lived credentials held
    on the host; these bypass the public login flow.
- **Authorization = a tiny enum claim `[player | system]` + scopes** where needed
  (`ResolveMatch`, `AutoBurn`, `UpdateBase` are `system`-only). Player tokens carry only
  `player` scope; no player op can mutate engine state machines directly except via the
  defined player ops.
- **Login throttling.** Per-IP and per-user-name attempt windows enforced at the proxy
  (Caddy/Nginx) + identity-context layer. API keys never replace passwords at Launch.
- **MFA / third-party social login deferred to 1.0** as a product decision.

## Rationale

- The patterns here are well-trodden and the libraries are battle-tested; we are not
  rolling crypto.
- On VPS Launch we add no external service/plan dependency; cost and ops surface stay
  minimal.
- Two-key split prevents a leaked player token ever being misinterpreted as system
  authority, hardening §3 system-only ops and §6.6 auto-burn exclusivity.
- Refresh reuse-detection gives near-opaque-session-level security with the
  Redis-less stateless JWT plan from ADR-0002.

## Consequences

- Positive: zero external auth deps, full audit of credential events, robust
  revocation via refresh rotation, clean `system` vs `player` separation feeds into
  all system-only engine ops.
- Negative: we own the password roster responsibility for Launch; backups must be
  encrypted (see ADR-0006);.rate-limited reset flow needed.

## Alternatives considered

- **External IdP (Ory Kratos / Authentik / Auth0 / Clerk).** Strong choice if social
  login or MFA is required sooner; rejected at Launch only to keep the VPS patch
  count down and the demo deploy a single binary + proxy + Postgres.
- **Opaque server-side sessions (no JWT).** Strongest revocation, but adds a row
  lookup per request and conflicts with the no-Redis, stateless edge strategy at
  Launch.
- **Pure JWT, no refresh-token rotation.** Rejected: cannot revoke on logout or
  credential rotation.