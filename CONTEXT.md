# Context — League Tokens Backend

Primary context file for agents. Load this before exploring.

## Reading Order

1. This file (CONTEXT.md) — glossary + ADR index
2. `docs/adr/` — read only the ADRs relevant to your task (see index below)
3. `specs/game_engine_spec.md` / `specs/game_design.md` / `specs/backend_system_design.md` — last resort, only if an ADR doesn't cover your question

## Ubiquitous Language

Map between game-engine terms and backend bounded contexts (ADR-0001).

| Term | Spec ref | Backend home | Notes |
|---|---|---|---|
| Aggregate (DDD) | — | each context owns its own | persistence boundary |
| `acc` | Spec 3.1, 5.1 | `game` (Ride aggregate) | per-ride liability, NOT a wallet balance; never enters Ledger |
| `base_at_lock` | Spec 4 Lock | `game` (Ride aggregate) | snapshot, lifetime immutable |
| Bounded Context | ADR-0001 | `internal/<ctx>` | each becomes a Go package |
| CommonPool | Spec 1, 5.6, 6.10 | `ledger` (equity account) | mechanical-mint-safety: Treasury/equity absorbs deficit |
| Currency | Spec 1 | `ledger` (`wallet.currency`) | single source of truth for balance |
| Favourite team | Spec 1, 3 Register | `game` (Player-season) | immutable after first Register per season |
| Feed | Spec 1 | `feed` (+ `schedule` storage) | external data boundary |
| `identity` | — | context | users, sessions, auth |
| Intent command | ADR-0001 | `game`→`ledger` | `LockIntent`, `BurnIntent`, `ReserveBuyIntent`, `GrantCurrencyIntent` |
| `Ledger` | ADR-0001 | context | sole money authority |
| `market` | Spec 10 | context | dormant at `[Launch]`, pluggable into ledger later |
| Match (real-life) | Spec 1, 2.3 | `schedule` | raw feed payload; `Resolved` result committed by feed |
| Match (resolved projection) | Spec 3.2 | `game` | `MatchResolved` projection; engine-owned |
| `player_TB` | Spec 8 | `rankings` | projection of burn/final-burn events, NOT money |
| Player (user) | Spec 1 | `identity` | auth-facing user identity |
| Player (season) | Spec 1, 3 Register | `game` (Player-season) | season-scoped registration, favourite lock |
| Reserve | Spec 1, 5.5 | `ledger` (`Team.reserve`) | drain-only at Launch, single balance account |
| Ride | Spec 1, 7 | `game` (Ride aggregate) | carries `state`, `streak`, `acc`, `tokens_locked`, `base_at_lock`, `match` |
| `team_basket` | Spec 8 | `rankings` | projection |
| Team entity identity | Spec 1 | `schedule` | id, name, metadata |
| `Team.base` | Spec 1, 5.4 | `game` (Team-price projection) | mutated by `UpdateBase` inside `ResolveMatch` |
| Tokens (per-team wallet) | Spec 1 | `ledger` (`wallet.tokens[*]`) | balance per (player, team) key |
| Treasury equity | ADR-0001 | `ledger` | absorbs mechanical-mint deficit (Spec 6.10) so the journal stays double-entry |
| Ubiquitous language | — | domain-modeling | terms above are authoritative; do not synonym-them in code |

## ADR Index — read only what touches your task

| ADR | File | When to read |
|---|---|---|
| 0001 | `docs/adr/0001-bounded-contexts.md` | Module boundaries, cross-context calls, Ledger as sole money authority |
| 0002 | `docs/adr/0002-persistence-and-consistency.md` | Postgres tx boundaries, game↔ledger command flow, outbox pattern |
| 0003 | `docs/adr/0003-api-edge-sse-idempotency.md` | REST/JSON API, SSE real-time, idempotency keys |
| 0004 | `docs/adr/0004-identity-auth.md` | Users, sessions, JWT, Ed25519, argon2id, player vs system auth |
| 0005 | `docs/adr/0005-system-triggers-scheduler-feed.md` | Auto-burn deadlines, feed ingestion, scheduler restart-safety |
| 0006 | `docs/adr/0006-deployment-and-observability.md` | VPS deploy, Docker Compose, Prometheus/Tempo, Grafana Cloud |
| 0007 | `docs/adr/0007-security-posture.md` | TLS, CORS, rate-limits, govulncheck, Docker secrets, PII |
| 0008 | `docs/adr/0008-package-layout.md` | Go package structure, `internal/` layout, sqlc boundaries |
| 0009 | `docs/adr/0009-scaling-strategy.md` | Monolith→microservices staged pathway, 1.0 targets |
| 0010 | `docs/adr/0010-money.md` | `shopspring/decimal`, NUMERIC(38,6), round-half-up, lint rules |
| 0011 | `docs/adr/0011-error-model.md` | `apperr.Error`, problem+json, typed error codes |
| 0012 | `docs/adr/0012-configuration.md` | env-driven config, Docker secrets, `caarlos0/env` |

## Spec Docs — last resort, only if ADRs don't cover it

- `specs/game_design.md` — game design intent, tuning levers, phasing. Read for "why" questions.
- `specs/game_engine_spec.md` — authoritative engine state machines, formulas, invariants (Spec N.M). Read for "what exactly happens" questions.
- `specs/backend_system_design.md` — backend architecture synthesizing all ADRs. Read for cross-cutting architecture overview, data model, sequence flows, or the per-endpoint API reference.
