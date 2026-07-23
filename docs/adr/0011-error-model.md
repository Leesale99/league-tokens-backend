# ADR-0011 — Typed Error Model (`apperr.Error`, problem+json)

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Domain layer returns errors. The HTTP layer must render `application/problem+json`
(RFC 7807). Idempotency-key collisions (ADR-0003) and §3.2 `AlreadyResolved` must map
to **machine-readable stable codes** so the player client can branch on them. Errors
need stable codes for client logic and an HTTP status for the wire; logging needs
optional structured context (no raw stacks sent to players).

## Decision

- **One domain error type** `apperr.Error` in `internal/infra/apperr`. Fields:
  - `Code string`         — stable dotted string (`"game.already_resolved"`).
  - `Msg string`          — safe-for-display, templated per code, no PII.
  - `HTTPStatus int`      — the wire status to map.
  - `Fields map[string]json.RawMessage` — optional structured payload (e.g.
    `{"round":14, "cutoff":"2026-07-22T20:00:00Z"}`).
  - `Cause error`         — wrapped underlying error; never serialized to the player.
- **One code → one HTTP status** mapping maintained in
  `internal/infra/apperr/codes.go`; a lint + test verifies uniqueness and
  determinism. New codes are additions only; codes never get re-mapped.

- **Sentinel errors** per context (`var ErrAlreadyResolved = apperr.New(
  "game.already_resolved", http.StatusConflict, "match already resolved")`).
  `errors.Is`/`errors.As` work transparently via `errors.Is`/`errors.As` on
  `apperr.Error`.

- **HTTP rendering**: `internal/http` middleware converts unknown Go errors to
  `apperr.ErrInternal` (logs the underlying, surfaces a generic `500` message);
  `apperr.Error` is rendered as `application/problem+json` per RFC 7807:
  ```json
  {
    "type": "https://league-tokens.example/problems/phase-closed",
    "title": "Round action phase closed",
    "code": "game.phase_closed",
    "detail": "Round 14 action phase ended at 2026-07-22T20:00:00Z.",
    "status": 409,
    "fields": { "round": 14, "cutoff": "2026-07-22T20:00:00Z" }
  }
  ```

- **Logging**: structured slog records include `code`, `op`, `subject_id`,
  `trace_id`, `request_id`. The stack is captured via OTel traces (ADR-0006),
  not duplicated into the player response.

- **No panics for invariant violations**. Spec §6 invariants surface as
  `apperr.Error` so the player/HTTP layer handles them uniformly. `panic` is
  reserved for genuinely unrecoverable programmer errors (init-time config
  corruption, broken signing key) which are caught by a top-level recover-only-
  log-and-500 handler.

## Canonical code table (initial)

| Code | HTTP | Spec ref | Meaning |
|---|---|---|---|
| `game.phase_closed` | 409 | §6.1 | round cutoff already passed |
| `game.insufficient_wallet_tokens` | 403 | §6.2 | wallet.tokens < lock amount |
| `game.insufficient_reserve` | 403 | §6.3 | reserve balance shortfall |
| `game.no_scheduled_match` | 409 | §6.4 | team has no `Scheduled` match this round |
| `game.invalid_state_transition` | 409 | §6.5 / §6.11 | ride state gate violated / terminal state |
| `game.system_op_only` | 403 | §6.6 | player token tried a system op |
| `game.favourite_already_set` | 409 | §6.8 | second Register in same season |
| `game.already_resolved` | 409 | §3.2 / §6.9 | `ResolveMatch` re-commit |
| `ledger.insufficient_balance` | 402 | §6.2 / §6.7 | `account` demand (LockIntent/BurnIntent) rejected |
| `ledger.mint_safety_alert` | 500 | §6.10 | mechanical-budget mint safety hit (observability alert) |
| `infra.idempotency_conflict` | 409 | ADR-0003 | idempotency-key reused with different command hash |
| `infra.idempotency_expired` | 422 | ADR-0003 | idempotency-key store entry past `expires_at` |
| `identity.credentials_invalid` | 401 | ADR-0004 | bad login |
| `identity.session_revoked` | 401 | ADR-0004 | refresh reuse / logout |
| `identity.rate_limited` | 429 | ADR-0004 | login throttle |
| `infra.phase_unknown` | 500 | — | defensive |
| `infra.internal` | 500 | — | unclassified (logged with stack) |

## Consequences

- Positive: every spec invariant carries a typed code; clients branch on it; logging
  joins with trace_id; HTTP errors match RFC 7807; tests assert on sentinels; new
  codes are purely additive; `fmt.Errorf` shapes disappear from domain packages.
- Negative: one more package; strict discipline to add every code to the table.

## Alternatives considered

- **Sentinel-only / `fmt.Errorf` chains.** Simpler but loses the client-machine-
  readable stable code.
- **`samber/oops`**. Stack-aware; redundant with OTel trace_id; adds a dependency.
- **Panic-recover on invariants.** Rejected: panics leak across request boundaries
  and break the typed contract.