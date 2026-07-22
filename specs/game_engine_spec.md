# League Tokens — Game Engine Spec

Authoritative definition of the **game engine**: its state machines, lifecycles, operations, formulas, constants, and invariants. Consumed by backend and frontend system architects to derive their own designs.

> **Scope.** Engine-only. Excludes market (deferred to `[Market]` addendum), API/data models, infrastructure, frontend, auth/identity, persistence choice.
> **Source of truth.** Where this doc and `game_design.md` agree, they agree. Where the design doc is silent, this spec decides.
> **Phase tags.** `[Launch]` MVP · `[Market]` end-of-MVP · `[Post-launch]` deferred.
> **Conventions.** Token sums are fixed-point, **6 decimals** (unit `1e-6`). All persisted arithmetic is rounded to **6 decimals, round-half-up** (default decimal rounding) at **every write boundary**: `UpdateBase`, `AccDelta` accrual, burn payout, reserve-buy price, and loss-destruction. There is no special-case `floor` anywhere; the previous "floor only at loss-destruction" rule is superseded. Persistence enforces the 6-decimal scale a second time at the column level (`NUMERIC(…,6)`).

---

## 1. State Ownership Summary

| State | Owner | Mutated by |
|---|---|---|
| `Season` | engine | system ops |
| `Round` | engine | system ops (phase transitions) |
| `Match` | engine (read-only payload from feed) | system op: result commit |
| `Team.base` | engine | system op: base update on match resolve |
| `Team.reserve` | engine | player op: reserve buy |
| `Player.wallet` (currency + per-team token balances) | engine | player ops, registration, system ops |
| `Player.favourite_team` | engine | registration (once, immutable per season) |
| `Ride` | engine | player ops (lock/burn/unlock/ride), system ops (resolve, auto-burn, final sweep) |
| `acc` (per-ride virtual TB) | engine | system op: accrual on win; realised on burn |
| `CommonPool` (currency) | engine | burns (pay), reserve buys (absorb), registration grant (mint) |
| TB / championship baskets / standings | engine | burn events |

External feeds supply: season config (teams, rounds), per-match schedule, per-match settled decimal odds, per-match win/loss result. The engine never deduces these.

---

## 2. Lifecycles

### 2.1 Season lifecycle

```
Created → RegistrationOpen → InProgress → FinalAutoBurn → FinalStandings → Closed
```

- `Created`: season config loaded (N teams, R rounds, K, constants table). No rounds active.
- `RegistrationOpen`: players may register. Rounds not yet active.
- `InProgress`: rounds iterate per Spec 2.2. Registration may stay open alongside (late joiners).
- `FinalAutoBurn`: fires once, when the **last match of round R resolves** — Spec 2.4. Transitions automatically.
- `FinalStandings`: championships frozen; standings read-only. MVP tiebreaks: TB desc, then oldest account (player) / team id (team).
- `Closed`: terminal. Each season is **isolated** at `[Launch]`; no cross-season carryover. Rollover is `[Post-launch]`.

### 2.2 Round lifecycle

```
ActionPhase → MatchPhase → Resolved → (next round ActionPhase | FinalAutoBurn)
```

- `ActionPhase`: opens when the previous round reaches `Resolved` (round 1 opens at `InProgress`). Player ops enabled.
- **Cutoff** (hard, schedule-driven): `scheduled_first_tipoff(round) − 1h`. Owned by the engine; not player-configurable. Past cutoff → `MatchPhase`; all player ops rejected with a typed `PhaseError`.
- `MatchPhase`: ride ops closed. Matches play per real-world schedule. Market stays open `[Market]`.
- `Resolved`: every match in the round has a committed result and base prices updated. Opens next round's `ActionPhase`, or triggers `FinalAutoBurn` if this is round R.

### 2.3 Match lifecycle

```
Scheduled → InPlay → Resolved
```

- `Scheduled`: known tipoff, settled odds supplied by feed (decimal, verbatim).
- `InPlay`: tipoff reached. No engine effect vs `Scheduled` other than cutoff already passed; the engine still treats result as pending.
- `Resolved`: result commit (Spec 3.2). Append-only at `[Launch]` (postponed/voided/corrected matches are a `[Post-launch]` problem — see `game_design.md` Open Questions).

### 2.4 Final auto-burn (endgame)

Triggers when the **last match of round R** reaches `Resolved`. Engine sweeps **every** `Ride` in state `WonPending` across **all players, all teams** and burns each (Spec 4.3 burn). No ride survives past season end. Then `Season → FinalStandings`.

---

## 3. System Operations (engine-internal, not directly player-invoked)

| Op | Trigger | Effect |
|---|---|---|
| `ResolveMatch(match)` | result payload arrives | commit result (append-only, idempotent on match id), settle all rides locked into that match, accrue acc on wins / destroy + forfeit on losses, update `Team.base`, recompute standings. |
| `AutoBurnDeadline(round)` | the round's cutoff timestamp fires | for every `WonPending` ride whose action window closes with this round's cutoff, burn it (Spec 4.3). |
| `FinalAutoBurn` | last match of round R resolves | burn all `WonPending` rides league-wide (Spec 2.4). |
| `UpdateBase(team, win)` | inside `ResolveMatch` per affected team | `base ← (base × 1.05).Round(6)` if win else `(base × 0.95).Round(6)`; clamp to `base > 0` (strictly positive; never reaches 0). No upper cap. |
| `Register(player, team)` | player registration request | grant 50 currency (mint from `CommonPool`), lock `favourite_team = team` for the season. **No token auto-buy at `[Launch]`** — first token acquisition is a normal reserve buy in round 1. |

### 3.1 Resolution mechanics (`ResolveMatch`)

For each team T in the match, `UpdateBase(T, did_T_win)` runs once. Then for every ride locked into this match:

- If the ride's team **won**: `acc += acc_delta` (Spec 5.1), `Ride.state ← WonPending`. The player's action window is the **next round's `ActionPhase`** (cutoff of round `current+1`). No further effect until the player acts or `AutoBurnDeadline` fires.
- If the ride's team **lost**: destroy `(tokens_locked × X).Round(6)` tokens (sink), return `tokens_locked − destroyed` to that player's wallet for that team, **forfeit all `acc`**, `Ride.state ← Lost` (terminal).
- A ride's `acc_delta` uses the match's **settled decimal odds**, verbatim from the feed.

### 3.2 Idempotency

`ResolveMatch` is idempotent on `match_id`: a second commit for the same match is a no-op (engine returns `AlreadyResolved`). MVP assumes no corrections; corrected results are a `[Post-launch]` admin reconciliation op.

---

## 4. Player Operations

All player ops validate Spec 6 invariants first and reject with a typed error otherwise.

| Op | Valid phase | Pre-state | Effect |
|---|---|---|---|
| `Register` | `RegistrationOpen` (or `InProgress` if late-join allowed) | new player | per Spec 3 system op `Register`. One-shot per player per season; favourite immutable. |
| `BuyFromReserve(team, amount)` | `ActionPhase` or `MatchPhase` (buy is always allowed `[Launch]`) | `wallet.currency ≥ (base × amount).Round(6)`, `reserve(team) ≥ amount` | `currency -= (base × amount).Round(6)` → `CommonPool`; `reserve(team) -= amount`; `wallet.tokens[team] += amount`. Unlimited up to reserve remaining. |
| `Lock(team, tokens)` | `ActionPhase` (this round only) | `wallet.tokens[team] ≥ tokens`, team has a `Scheduled` match this round | freeze `base_at_lock = Team.base` (snapshot, ride-lifetime); create new `Ride` with `streak = 0`, `acc = 0`, `tokens_locked = tokens`; `wallet.tokens[team] -= tokens` (tokens become ride-held); `Ride.match = team's match this round`; `Ride.state = Locked`. **Multiple concurrent rides per team allowed** (each independent, own streak). |
| `Ride(ride_id)` | `ActionPhase` | `Ride.state = WonPending` | continue the chain: set `Ride.match = team's match this round` (the team's only match this round), `streak += 1`, `Ride.state = Locked`. `base_at_lock` and `tokens_locked` **unchanged**. |
| `Burn(ride_id)` | `ActionPhase` | `Ride.state = WonPending` | `tb_credit = tokens_locked + acc`. Player TB += tb_credit; team basket += tb_credit; `CommonPool` pays currency `(base_at_lock × tokens_locked).Round(6)` → `wallet.currency`; tokens destroyed (sink); `Ride.state = Burned` (terminal). |
| `Unlock(ride_id)` | `ActionPhase` | `Ride.state = WonPending` | tokens return to `wallet.tokens[team]`; `acc` forfeited (drops, not credited anywhere); `Ride.state = Unlocked` (terminal). Near-redundant `[Launch]`; earns market value `[Market]`. |
| *(no action by cutoff)* | — | `Ride.state = WonPending` | system fires `AutoBurnDeadline` → behaves as `Burn`. |

**Notes**
- `WonPending` is the **only** state from which a player fork (`Ride | Burn | Unlock`) is legal. A `Lost` ride is auto-finalised at resolution (no player op).
- Ride ops reference the round whose cutoff applies to that ride, which is the round **following** the round of the match that produced the win (i.e. the player decides during the next action phase).
- Wallet-burn of un-ridden tokens is **`[Post-launch]`**. At `[Launch]`, TB is produced only by burning resolved winning rides.

---

## 5. Economy Formulas

### 5.1 Per-win acc accrual

```
acc_delta = (tokens_locked × (odds_settled − 1) × (1 + streak × s)).Round(6)
acc       += acc_delta           // on each win, at ResolveMatch time
streak    += 1                   // on subsequent Ride op (next-round continuation)
```
`Round(6)` is round-half-up to 6 decimals (see Spec 6.12 — same rounding applies to every persisted arithmetic step).

- `tokens_locked`: ride-held tokens (constant across the chain; loss is a single terminal event, no mid-chain compounding).
- `odds_settled`: settled decimal odds of the winning match, verbatim from result feed.
- `streak`: 0-indexed **ride** chain position. Decoupled from the real team's streak — a ride created when the team is already on a real 3-win streak starts at `streak = 0`.
- `s`: streak coefficient (constants table, default 0.20).

### 5.2 Loss

```
destroyed = (tokens_locked × X).Round(6)     // X = loss burn %, constants table, default 0.25
returned  = tokens_locked − destroyed
// destroyed tokens leave existence (sink); returned → wallet.tokens[team]
// acc forfeited to 0; Ride.state ← Lost (terminal)
```

`Round(6)` is round-half-up to 6 decimals (Spec 6.12) — this replaces the previous `floor`
rule. Only ever one loss event per ride (chain ends).

### 5.3 Burn (player or auto)

```
tb_credit   = tokens_locked + acc
player_TB  += tb_credit
team_basket += tb_credit                    // Team Championship
wallet.currency += (base_at_lock × tokens_locked).Round(6)   // paid by CommonPool (mints on deficit — mechanical invariant, never +EV); half-up to 6 dp (Spec 6.12)
// tokens_locked destroyed (sink)
```

### 5.4 Base price

```
base ← (base × 1.05).Round(6)  if team won  last match
base ← (base × 0.95).Round(6)  if team lost last match
// applied once per team per match, inside ResolveMatch
// invariant: base > 0 (strictly positive; multipliers clamped to a tiny epsilon at the boundary)
// existing rides are immune: base_at_lock already frozen
// .Round(6): half-up to 6 decimals, keeps base at scale 6 across the whole season (Spec 6.12)
```

### 5.5 Reserve buy (only token faucet at `[Launch]`)

```
price       = (Team.base × amount).Round(6)   // current base, not frozen; half-up to 6 dp (Spec 6.12)
wallet.currency  -= price    → CommonPool
reserve(team)    -= amount
wallet.tokens[team] += amount
// reserve is drain-only at [Launch] (never refills); refill is a [Post-launch]/sim lever
```

### 5.6 Currency loop

Closed. Sources of currency: registration grants (one-time). Sinks: reserve buys (→ `CommonPool`) which then pay burns. Burns pay `base_at_lock × tokens` into currency; token destruction (loss, burn) destroys tokens **without** destroying currency. No other mint except the mechanical `CommonPool` deficit safety (Spec 6 invariant).

---

## 6. Engine Invariants (enforced on every op; reject with typed error)

1. **Phase guard.** `Lock/Ride/Burn/Unlock` require the round governing that ride to be in `ActionPhase` and the engine clock before that round's cutoff. `BuyFromReserve` allowed in `ActionPhase` and `MatchPhase` (no phase gate at `[Launch]`).
2. **Sufficient wallet.** `Lock`: `wallet.tokens[team] ≥ tokens`. `BuyFromReserve`: `wallet.currency ≥ base × amount`.
3. **Sufficient reserve.** `BuyFromReserve`: `reserve(team) ≥ amount`.
4. **Lock target.** `Lock` requires the team to have a `Scheduled` match in the current round.
5. **Ride state gate.** `Ride/Burn/Unlock` require `Ride.state = WonPending`. `Lock` requires no pre-existing ride (it creates one). `Ride` requires the team to have a `Scheduled` match in the current round.
6. **Auto-burn exclusivity.** `AutoBurnDeadline` and `FinalAutoBurn` are system-only, fired by the cutoff clock or the last-match-resolved event. Players cannot invoke auto-burn or undo it.
7. **No negative balances.** `wallet.currency ≥ 0`, `wallet.tokens[*] ≥ 0`, `reserve[*] ≥ 0`, `acc ≥ 0`, `Team.base > 0`. Any op that would cross zero is rejected (or clamped at the epsilon boundary for `base`).
8. **Favourite immutability.** `Player.favourite_team` set exactly once at `Register`; never mutated thereafter within the season.
9. **Result append-only.** A `ResolveMatch` for an already-resolved match is a no-op. MVP does not support corrections.
10. **CommonPool mechanical safety.** Burns always pay `base_at_lock × tokens_locked`; if the pool would go negative it pays anyway (mints). This is an invariant guarantee, not a player-facing lever and not a sim lever. The closed loop makes deficit structurally unreachable; a negative balance is an observability alert, not gameplay.
11. **Terminal states.** `Lost`, `Burned`, `Unlocked` are terminal; no op may mutate them.
12. **Precision.** All persisted token/currency arithmetic is rounded to **6 decimals, round-half-up** (default decimal rounding) at **every write boundary**: `UpdateBase`, `AccDelta` accrual, burn currency payout, reserve-buy price, and loss-destruction. There is no `floor` anywhere; the prior `floor` rule at loss-destruction is superseded. Inputs are 6-decimal fixed-point (`NUMERIC(38,6)` storage); the result of every persisted arithmetic operation is `Round(6)` before write. `Round(6)` is round-half-up to 6 decimals (the default `decimal.Decimal` policy after `decimal.DivisionPrecision = 6`).

---

## 7. Ride State Machine

```
                         (Lock)
   ───────────────────►  Locked
                            │
                  ResolveMatch on ride.match
                 ┌──────────┴──────────┐
            win │                        │ loss
                ▼                        ▼
          WonPending                    Lost (terminal)
            │ │ │
  Ride op ──┘ │ └── Burn op ──────► Burned (terminal)
              │
   Unlock op ─┘─────────────────► Unlocked (terminal)
              │
   (no op by cutoff) ── system: AutoBurnDeadline ──► Burned (terminal)
              │
   (season end)  ── system: FinalAutoBurn ──► Burned (terminal)

  Ride op: state returns to Locked, streak += 1, match = team's match this round.
```

- `WonPending` is the **only** decision state. One fork per round: `Ride`, `Burn`, `Unlock`, or inaction→auto-burn.
- `base_at_lock` and `tokens_locked` are set at the first `Locked` and **never change** for the ride's lifetime (including across `Ride` cycles).

---

## 8. Championships & Standings (engine-computed)

- **Team Championship basket (per team)**: `Σ tb_credit` over every burn event (player + auto + final) on a ride of that team. At `[Launch]` this is **ride-burns only** (no wallet-burn; gated to `[Post-launch]`).
- **Player Championship total (per player)**: `Σ tb_credit` over that player's burn events. Currency never ranks.
- **Tiebreak (MVP)**: TB desc, then oldest account (player board) / team id (team board). Full tiebreaks `[Post-launch]`.
- **Boards at `[Launch]`**: Team, Player, Team contributors (with favourite-team allegiance). Net Worth board ships with `[Market]`.

---

## 9. Constants Table (sim-tunable; engine config)

| Symbol | Name | Default | Engine role |
|---|---|---|---|
| `X` | loss burn % | 0.25 | loss token destruction |
| `s` | streak coefficient | 0.20 | acc_delta streak factor |
| `W` / `L` | base win/loss multipliers | 1.05 / 0.95 | `UpdateBase` |
| `K` | per-team token supply | 200 | initial `reserve(team)` |
| `G` | registration grant | 50 currency | `Register` mint |
| `epsilon` | base lower bound | 1e-6 | `base > 0` clamp |
| `cut_off` | action-phase lead time | 1h | round cutoff |
| precision | token decimals | 6 | fixed-point unit |
| rounding | persisted-arithmetic rounding mode | half-up | applies at every write boundary (Spec 6.12) |

Each is a per-season engine config constant. `X`, `s`, `W`, `L`, `K`, `G` and `rounding` are **sim outputs**, not design inputs — see `game_design.md` Spec 10 for sim verification obligations. Sell cap (2× base) and taker fee (1%) are `[Market]` addendum constants, not engine-core.

---

## 10. Out of Scope (deferred addenda)

- **`[Market]` addendum.** Player order book, sell cap (2× base), maker/taker fees, Net Worth board, defensive trading. Architecture must keep the market pluggable. The engine exposes: `Team.base` (sell cap input), `reserve(team)` (fallback ask), and burn/reserve accounting unchanged when market sells occur (market trades are wallet↔wallet token transfers with a fee sink, plus a currency movement).
- **`[Post-launch]`.** Wallet-burn, staking, idle-policy (auto-ride vs auto-burn), live match centre, full tiebreaks, median-scaled grant, basket cap, season-2 rollover, playoffs, postponed/cancelled/voided/corrected-match handling.