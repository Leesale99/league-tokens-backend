# ADR-0001 — Bounded Contexts and the Ledger as Sole Money Authority

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner
Supersedes: —
Superseded by: —

## Context

The `game_engine_spec.md` defines state ownership per engine entity but says nothing about
backend module boundaries. We need a cut that:

- maps cleanly to the engine's State Ownership table,
- keeps the eventual `[Market]` addendum pluggable without rewrites,
- fits a Modular Monolith deployable on a 1-core / 4 GB / 50 GB VPS for 10k active users,
- scales module-by-module into microservices for the 1.0 release.

## Decision

Seven bounded contexts plus one shared kernel, so the backend modules are:

| # | Context | Owns (write authority) | Consumes (read-only) |
|---|---|---|---|
| 1 | `identity` | users, sessions, auth | — |
| 2 | `schedule` | raw feed payload: teams, rounds, matches, settled odds, results | feed adapter only |
| 3 | `game` | engine state machines (Season, Round, Player-season, Ride, `acc`, `Team.base`), ResolveMatch, AutoBurn, FinalAutoBurn, Register | `schedule` events, `ledger` command results |
| 4 | `ledger` | ALL monetary/token balance writes: `CommonPool`, `wallet.currency`, `wallet.tokens[*]`, `Team.reserve`. Double-entry journal. Sole authority for balance invariants §6.2/§6.3/§6.7 | commands from `game`, `market`, `identity` (registration grant) |
| 5 | `rankings` | in-engine projections: `player_TB`, `team_basket`, standings/boards, tiebreaks | burn/reserve events from `ledger`+`game` |
| 6 | `market` | order book, matches, fills (pluggable, dormant at `Launch`) | `ledger` balance commands, `game` base price |
| 7 | `feed` (infra adapter) | ingestion boundary for external schedule/odds/results | outside world |
| — | `infra` (shared kernel) | in-process event bus, job scheduler (cutoff/auto-burn timers), outbox, observability, crypto, config | all |
| — | `rankings` et al. own read models | — | — |

### Key invariants of the split

1. **Ledger is the sole authority over balances.** `game`, `market`, `rankings` emit *intent
   commands* (`LockIntent`, `BurnIntent`, `ReserveBuyIntent`, `GrantCurrencyIntrent…`) and
   react to `Accepted`/`Rejected` events. They never read balances to authorize an op.
   This kills the stale-read race class and gives a natural audit trail.
2. **Team entity is fragmented.** `Team` identity lives in `schedule`; `Team.base` lives in
   `game` (mutated by `UpdateBase` inside `ResolveMatch`); `Team.reserve` lives in `ledger`.
   Facets are linked by `team_id`. No single Team aggregate exists.
3. **`Schedule` is read-only outside its feed adapter.** `Game` consumes `ResultAvailable`
   events from `schedule`, mutates only its own aggregates (Ride, `Team.base`) and emits a
   `MatchResolved` projection. It never writes back to `schedule`.
4. **`acc` stays with `game` (Ride aggregate)** — it is a per-ride liability produced by
   the engine formulas, not a wallet balance.
5. **`player_TB` / `team_basket` live in `rankings`** as projections of burn/reserve
   events from `game`+`ledger`. They are not money.
6. **Player / Registration season-scoped aggregate lives in `game`** (favourite_team
   immutability, registration state). Its currency side-effect (`GrantCurrency`) is a
   command to `ledger`. Revisit splitting a `player` context at the 1.0 cut if it grows.

## Consequences

- Positive: single source of truth for money; clean audit log; `[Market]` reuses the same
  Ledger commands as `game` later; Ride/burn invariants stay inside `game`; `schedule`
  can be sourced from any feed (swap adapter) without touching engine logic.
- Negative: `game` and `ledger` are not independently writable in `Launch` (synchronous
  in-process command). This is a local function call in-process, negligible at 10k users,
  but it pins the module split for 1.0: `game`+`ledger` must scale together unless we move
  to event-driven commands (outbox + eventual consistency) — recorded as `[1.0 candidate]`.
- Currency grant at Register is a Ledger double-entry `credit wallet / debit CommonPool
  equity`, not minting out of thin air. §5.6 wording is preserved by treating `CommonPool`
  as an equity account that can take a negative book value (the §6.10 "mechanical mint on
  deficit" guard becomes: the **Treasury equity** account absorbs it, never rewritten).

## Alternatives considered

- **Merge Treasury+Ledger into `game` (original proposal).** Rejected: couples money
  with gameplay formulas; blocks clean `[Market]` split; loses audit-trail simplicity.
- **Game pre-checks balance, Ledger re-validates on apply.** Rejected: opens a TOCTOU
  race for write-throughput we don't need at 10k users; harder audit.
- **Split `player` as a 9th context now.** Deferred: no second owner yet; keep on the
  1.0 candidate list.