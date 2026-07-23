# ADR-0007 — Security Posture (Secure-by-Design)

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Secure-by-Design is a hard requirement stated up-front. Players store value (tokens +
currency), and the engine has system-only ops (`ResolveMatch`, `AutoBurn`,
`FinalAutoBurn`) that must never be invocable by a player token (spec §3, §6.6).
Launch runs on a single VPS reachable from the public internet.

## Decision — Secure-by-Design baseline at Launch

### Authn

- Per ADR-0004: **two Ed25519 signing keys**, Argon2id password hashing, refresh-token
  rotation with reuse-detection, **system vs player** token audiences. System tokens
  issued only to in-process feed/scheduler adapters.

### Transport

- **HTTPS-only** via Caddy auto-ACME; HTTP→HTTPS redirect; **HSTS 1y + preload**.
- DB socket localhost-only inside the Compose network; no DB port published to the host.

### Response headers

- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `Permissions-Policy: geolocation=(), microphone=(), camera=()`
- `Cache-Control: no-store` on mutating endpoints and on the SSE channel.
- `Content-Type: application/problem+json` on errors.

### CORS

- Explicit allowlist of the player-client origin(s) (env-driven); `OPTIONS` preflight
  enabled; **no `*` when credentials are involved**. SSE also gated by same-origin CORS.

### Session + CSRF

- JWT in a `HttpOnly`, `Secure`, `SameSite=Strict` cookie for the player client.
- `SameSite=Lax`+ **double-submit token** only where cross-site top-level nav must work
  (currently nowhere — kept for the future `[Market]` web flows).
- Refresh rotation revokes the whole session family on reuse (ADR-0004).

### Rate limiting

- **Caddy** per-IP token-bucket e.g. 60 req/min (sliding window).
- **Go middleware** per-JWT-subject token-bucket, e.g. **12 mutating op/min** (players
  only Lock/Burn/etc. a few times per round regardless). SSE subscription counts capped per
  subject to bound idle-connection memory.

### Input validation + SQL safety

- Every request body validated via `go-playground/validator` with allowlist rules
  (ranges, enums, fixed-point precision), **never** a denial-by-omission check.
- **SQL**: schema access exclusively via `sqlc`-generated parameterized queries; raw
  string concatenation into queries banned at lint time (no `db.Query(fmt.Sprintf(...))`).

### Secrets

- Docker secrets only — mounted read-only at `/run/secrets/`. Never env vars, never
  committed, never logged. Ed25519 key files `0600`. Provider API key, OTLP token,
  backup bucket credentials all via secrets.

### Deps & supply chain

- `govulncheck` runs in CI; `golangci-lint` enables `gosec`, `govet`, `errcheck`,
  `unused`, `staticcheck`, `bodyclose`.
- Renovate bot opens PRs on dep updates; CI gates merges.
- No `//go:build ignore` bypass committed.

### PII minimisation

- At Launch we collect **email + hashed password only**. No real name, no payment info,
  no third-party identity. Number of unique balances far more sensitive than PII here.

### Audit log of money + auth

- Every money-mutating op produces durable records: `ledger.journal_entries`,
  `game.ride_events` (ADR-0002).
- `identity` auth events (login, refresh rotation, password reset, login failure
  above threshold) written as structured logs with `subject_id`, `ip`, `user_agent`,
  `trace_id`. Never the refresh token or password.

### Encryption at rest

- Postgres data volume on VPS provider's encrypted block storage (or full-disk LUKS
  fallback). `pg_dump` artefacts pushed via **rclone** with server-side encryption +
  bucket side encryption. DB connection TLS for cross-process in 1.0; local socket
  within Compose at Launch.

### DDoS surface

- **Cloudflare free tier** sits in front of Caddy: caches hot read-only GETs (boards,
  season/round status — read-heavy traffic), applies managed WAF rules; only the SSE
  endpoint must bypass cache (Cloudflare supports it). Player mutating endpoints are
  cached away. Managed WAF becomes a 1.0 candidate if free-tier rules are insufficient.

### Specific game-engine guarantees enforced in code

- §3.2 idempotency on `match_id`: `ResolveMatch` is a no-op on already-resolved match
  (`AlreadyResolved` error returned).
- §6.6 auto-burn exclusivity: `AutoBurnDeadline`, `FinalAutoBurn`, `UpdateBase` are
  **`system`-token-only** endpoints — no `player` token can reach the code path.
- §6.8 favourite immutability: `Register` is one-shot; subsequent writes to
  `favourite_team` are blocked by the application layer AND by a Postgres
  **conditional CHECK trigger** preventing update of the column.
- §6.9 result append-only: `ResolveMatch` writes status on a `WHERE status='Scheduled'`
  guard; a re-commit returns `AlreadyResolved`.
- §6.11 terminal states (`Lost`, `Burned`, `Unlocked`): Postgres CHECK constraints block
  any row in a terminal state from being mutated again (handled by the optimistic-version
  update + state-machine guard).
- §6.12 precision: all token math done in `int64` representing 1e-6 units; financial
  helper package `internal/money` with overflow-add/sub protection; the only `floor`
  is `LossDestroy` and it explicit.

## Consequences

- Positive: every spec invariant that is a security/correctness commitment has a
  *concrete* enforcement mechanism at code, DB-constraint, or proxy layer; no single
  class of token can become another; supply chain hygiene; minimal PII reduces breach
  blast radius.
- Negative: per-subject rate limits and Cloudflare caching need to be tuned before
  opening Launch; SSE rules + cache-bypass tested under load.

## Alternatives considered

- **Skip Cloudflare in front.** Direct connection to Caddy. Rejected: free-tier DDoS
  protection + WAF + caching for read-heavy boards is cheap insurance.
- **WebAuthn at Launch.** Stronger auth but premature UX for a demo; deferred to 1.0
  per ADR-0004.
- **Full-disk encryption on VPS only.** Useful as a belt-and-braces; if the provider
  offers encrypted block storage that wins on CPU; otherwise LUKS fallback.