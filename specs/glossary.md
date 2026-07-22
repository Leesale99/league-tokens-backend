# Glossary — League Tokens backend

Map between `game_engine_spec.md` terms and the backend bounded contexts (ADR-0001). This file is appended to as the design matures.

| Term | Spec ref | Backend home | Notes |
|---|---|---|---|
| Aggregate (DDD) | — | each context owns its own | persistence boundary |
| `acc` | §3.1, §5.1 | `game` (Ride aggregate) | per-ride liability, NOT a wallet balance; never enters Ledger |
| `base_at_lock` | §4 Lock | `game` (Ride aggregate) | snapshot, lifetime immutable |
| Bounded Context | ADR-0001 | top-level backend module | each becomes a Go package `internal/<ctx>` |
| CommonPool | §1, §5.6, §6.10 | `ledger` (equity account) | mechanical-mint-safety lives as: Treasury/equity absorbs deficit, never rewritten |
| Currency | §1 | `ledger` (`wallet.currency`) | single source of truth for balance |
| Favourite team | §1, §3 Register | `game` (Player-season aggregate) | immutable after first Register per season |
| Feed | §1 | `feed` (+ `schedule` storage) | external data boundary |
| `identity` | — | context | users, sessions, auth |
| Intent command | ADR-0001 | `game`→`ledger` | e.g. `LockIntent`, `BurnIntent`, `ReserveBuyIntent`, `GrantCurrencyIntent` |
| `Ledger` | ADR-0001 | context | sole money authority |
| `market` | §10 | context | dormant at `[Launch]`, pluggable into ledger later |
| Match (real-life) | §1, §2.3 | `schedule` | raw feed payload; `Resolved` result committed by feed |
| Match (resolved projection) | §3.2 | `game` | `MatchResolved` projection; engine-owned |
| `player_TB` | §8 | `rankings` | projection of burn/final-burn events, NOT money |
| Player (user) | §1 | `identity` | auth-facing user identity |
| Player (season) | §1, §3 Register | `game` (Player-season aggregate) | season-scoped registration, favourite lock |
| Reserve | §1, §5.5 | `ledger` (`Team.reserve`) | drain-only at `Launch`, single balance account |
| Ride | §1, §7 | `game` (Ride aggregate) | carries `state`, `streak`, `acc`, `tokens_locked`, `base_at_lock`, `match` |
| `team_basket` | §8 | `rankings` | projection |
| Team entity identity | §1 | `schedule` | id, name, metadata |
| `Team.base` | §1, §5.4 | `game` (Team-price projection) | mutated by `UpdateBase` inside `ResolveMatch` |
| Tokens (per-team wallet) | §1 | `ledger` (`wallet.tokens[*]`) | balance per `(player, team)` key |
| Treasury equity | ADR-0001 | `ledger` | absorbs mechanical-mint deficit (§6.10) so the journal stays double-entry |
| Ubiquitous language | — | domain-modeling | terms above are authoritative; do not synonym-them in code |

More terms appended as decisions close.