# League Tokens — Game Design

A fantasy-economy game on a real basketball league. Players buy team **Tokens** with in-game **Currency**, lock them into real matches, ride winning streaks, and **burn** them for **TB** — the only score that matters. Two championships run all season: fans push their team up the **Team Championship**, individuals climb the **Player Championship**.

> **Central tension:** burn for your team's basket, or maximise your own TB. You cannot fully do both.

**Audience:** humans and agents. This doc defines *what the game is and why*. It excludes:
- Engine math, edge cases, state machines → `game_engine_specs.md`
- Infrastructure, APIs, data models → `backend_system_design.md` / `frontend_system_design.md`

**Phase tags:** `[Launch]` MVP soft launch · `[Market]` end-of-MVP, priority 1 · `[Post-launch]` deferred, no committed date

---

## 1. Design Pillars

1. **One score, many paths.** TB decides both championships. Currency is fuel, never victory.
2. **Every week, a real decision.** The lock — which team to back and how much to commit — has teeth from round 1.
3. **Underdogs matter.** High variance, rare jackpots — viable strategy, not charity.
4. **Consequences are honest.** You risk what you've built (acc) and a slice of what you paid (stake).
5. **Least complexity that preserves the above.** Every system earns its seat.

## 2. League & Season Shape

- **Configurable per season:** N teams, R rounds. (Sim corpus: EuroLeague 18 teams / 34 rounds; next season: 20 teams.)
- Real schedule, real results, real bookmaker odds per match.
- **Round lifecycle:** Action Phase (player ops open) → Match Phase (ops closed, matches play) → results committed → next round opens.
- **MVP season arc:** regular season → final round auto-burn → standings final.
- **Playoffs:** `[Post-launch]` (see Open Questions).

## 3. Core Assets & Economy

| Asset | Definition |
|---|---|
| **Token** | Per-team asset. Bought from a finite team **reserve**, locked into matches, burned for TB. |
| **Currency** | In-game money. Fuel for everything; worthless as a score. **Closed loop** — supply fixed at registration grants, no faucet, no mint. |
| **TB** | Score unit. Produced *only* by burning. Each burned token contributes **1 TB**; the ride bonus (**acc**) adds TB on top. Fills team baskets + player totals. |
| **acc (virtual TB)** | Per-ride accumulator, accruing with each win. Realised as TB on burn (or auto-burn); forfeited on loss or unlock. |
| **Base price** | Per-team engine price. Starts at **1.0**; ×1.05 per win, ×0.95 per loss. Drives reserve ask, sell cap, and burn currency return. |
| **base_at_lock** | The team's base frozen at lock time. Determined for that ride's lifetime; sets the currency returned on burn. |
| **Reserve** | Per-team finite token supply (K coeff, sim-tuned). When emptied, that team is circulating-supply-only. |
| **Common pool** | The house bank. Funds all burn currency returns; mints on deficit (mechanical safety, not a faucet — no +EV exploit exists). |

### Rules that hold the economy together

- **Finite reserves.** Every token in circulation was bought; scarcity is real. When a reserve empties, that team is circulating-supply-only.
- **No house floor.** Reserve sells at `base`; burn pays `base_at_lock × tokens`. Both can fall below 1.0 — losing teams' tokens genuinely crash.
- **Burn-buy-back gap.** Burning pays your frozen `base_at_lock`; re-arming costs today's price. Every burn cycle shrinks your position — the scarcity engine and the whale throttle.
- **Closed currency loop.** Supply is fixed at `Σ registration grants`. Burns return currency from the common pool; reserve buys absorb it; burn-on-loss destroys tokens without destroying currency. No faucet, no mint, no yield. Inflation is bounded by onboarding; deflation is impossible (currency never leaves the pool except via burn-back).

## 4. The Weekly Loop

**Action Phase** (opens after previous round commits, closes ~1h before first tipoff):

1. **Lock** tokens into any match this round (creates a *ride*)
2. **Ride / Burn / Unlock** any winning ride from previous rounds
3. **Trade** on the market `[Market]`

**Match Phase:** ride ops closed. Watch your teams; notifications bring you back. Market stays open `[Market]`.

### The fork (after every win)

| Action | You get | You give up |
|---|---|---|
| **Ride** | Chain continues — acc and stake ride into the next match | Safety: a loss now costs acc **and** a stake slice |
| **Burn** | Tokens + acc become TB (both championships) + currency stake-back at `base_at_lock × tokens` | All future upside of this chain |
| **Unlock** | Tokens back to wallet (sell at premium `[Market]`) | The entire acc |

**Honest note:** pre-market, *unlock* is nearly dead (a loss returns stake anyway). The full fork activates with the market. Signposted in UX.

## 5. The Ride — Win, Lose, or Show Up Late

One commitment, two reward outputs, one risk rule.

### Win

Per-win contribution formula (sim-tuned coefficient):

```
acc_delta = tokens_locked × (odds_settled − 1) × (1 + streak × s)
```

- `tokens_locked`: tokens committed to the ride (frozen across the chain)
- `odds_settled`: bookmaker odds of the winning match
- `streak`: 0-indexed chain position of this win (first win = 0)
- `s`: streak coefficient, default **0.20**, sim-tunable

The streak factor grows linearly with chain length. First win contributes at base value; each additional win contributes at a 20% increment. Top-team chains ride to ~5–6 wins before EV inverts (burn threshold); underdog paths burn on first win (jackpot realization).

### Loss

- **X% of locked tokens destroyed** (pure sink, no TB). Default **X=25%**, sim-tunable.
- **acc forfeited in full** (100%). Loss ends the chain.
- Remaining tokens return to wallet.
- Locking is a real bet from round 1.

### No action by deadline → auto-burn

Inactivity harvests and parks you — never punished, merely capped. Resolves as a burn: tokens + acc → TB, currency returned at `base_at_lock × tokens`.

### Fairness across the table

Favourites ride longer (lower-variance grind, ~6-win chains), producing modest acc per chain. Underdogs burn on first win (rare jackpot, ~25 TB per 10 tokens at 3.5 odds), plus the token count as TB on burn. Expected acc and expected token loss share the same odds factor — the exchange rate is identical at 1.3 and 3.5. Only variance differs.

The streak factor extends top-team chain lengths but applies equally to any team on a winning run. Longer chains produce disproportionate score via the streak factor, bounded by loss risk.

## 6. Championships & Leaderboards

**Team Championship** — sum of all TB burned for each team (token count + acc on every burn, including wallet-burns of un-ridden tokens). **No cap.** Two organic balancers:

1. **Defensive trading** — rivals sell your team's tokens at premium, taxing your re-arm `[Market]`
2. **Fat-odds + cheap entry fills underdog baskets** — losing teams' tokens crash in price, so underdog entry is cheap; fat-odds wins produce large TB jackpots; burns (including wallet-burns of cheap tokens) fill underdog baskets. Trader greed equalizes championship baskets as a side effect.

**Player Championship** — total TB. Currency never ranks.

**Boards (3 + Net Worth `[Market]`):**

| Board | Ranks | Filters |
|---|---|---|
| Team | 20 teams by basket TB | — |
| Player | all players by TB | rookie (join date) |
| Team contributors | burners per team, allegiance shown by favourite-team logo | our fans / rivals |
| Net Worth | wallet + holdings value `[Market]` | — |

MVP tiebreak: TB desc, then oldest account (player) / team id (team). Full tiebreaks `[Post-launch]`.

## 7. The Market `[Market]`

Full player order book per team — **the heart of the complete game**, shipped end-of-MVP as priority 1. Architecture must leave the option open as a drop-in.

Pre-market, the seller side is thinner than the buy side (players primarily hold their favourite team's tokens; cross-team holdings accumulate slowly). Defensive trading emerges from speculative cross-team accumulation; whether it is thick enough to brake top-team domination is a **sim question, not a design assertion**. If insufficient, a `[Post-launch]` seed mechanism (rival-team starter tokens, market activation grant, or staking-as-seller-side) is the lever.

- Sell cap 2× base; no buy cap. Reserve is the fallback ask at `base`, never bids.
- Fees: 1% taker / 0% maker — player market-making is a real archetype.
- Defensive trading is intended PvP, not abuse.
- Ships with the Net Worth board — the profit path gets its podium the day it exists.

## 8. Endgame

### Final round auto-burn

After the last resolved match of the regular season, **all pending winning rides auto-burn immediately**: tokens + acc realise as TB; currency returns at `base_at_lock × tokens`. 

### Playoffs `[Post-launch]`

Playoff mechanics (cascading burn war, eliminated-team freezes, wallet-burn dynamics, survivor riding) are deferred. See Open Questions.

## 9. Players & Anti-Abuse

- **Registration:** choose a **favourite team — locked for the season**; its logo follows you everywhere.
- **Grant:** **50 Currency** (fixed). 5 favourite-team tokens are auto-purchased at base 1.0 on registration (cost 5 from the grant); player starts with **45 Currency + 5 favourite-team tokens**. The lock decision starts on round 1.
- **Late joiners:** accepted limitation — priced out of hot teams, steered to cheap underdogs (which the game wants anyway). Rookie filter gives them their own race. Median-scaled grant is the documented lever if churn data proves the problem.
- **Session hooks `[Post-Launch]`:** three notifications — ride resolved ("Won vs Madrid — ride or burn?"), deadline reminder, favourite-team result. Live match centre.

**Anti-abuse:**
- One account per person (email/SSO), API rate limits. No trading API `[Launch]`.
- Structurally limited manipulation: 2× sell cap, reserve fallback, price self-correction.
- **Whale throttles are organic:** burn-buy-back gap + burn-on-loss decay + finite reserves. No special rules.
- **Closed currency loop — no mint exploit exists.** Burns return exactly the original stake; the only economy injections are one-time registration grants.

## 10. Tuning Levers — Owned by Simulation

Historical EuroLeague data is the pre-launch simulation corpus. These constants are *outputs* of sims, not design decisions:

| Lever | Start | What sims must verify |
|---|---|---|
| X (loss burn %) | 25% | Reserve survives the season; loyalist grind painful but viable |
| s (streak coefficient) | 0.20 | Chain length, jackpot magnitude, championship balance |
| Base multipliers | ×1.05 / ×0.95 | Price divergence meaningful by ~R5–8; no runaway spirals |
| Token supply (K) | 200 | Hot-team depletion timing vs. season length |
| Grant G | 50 | Season-long participation on one grant |
| Sell cap | 2× base | No cornering of low-base teams; thin sell-side brake |
| Taker fee | 1% | Sufficient to fund market-making without chilling volume |

**Flagged interactions:**
- Burn-on-loss accelerates token destruction (reserve pacing).
- Streak factor inflates long-chain payouts (championship distribution).
- No floor → losing teams' bases can crash toward near-zero (UX must surface crashing tokens; sims verify no exploitable loop emerges).
- Currency supply fixed post-onboarding — sims verify late-season liquidity doesn't dry up before `[Market]` ships; underdog loyalist sustainability depends on cheap re-arming with crashed tokens.

## 11. Phasing Summary

| Phase | Ships |
|---|---|
| `[Launch]` | Full ride loop (lock/ride/burn/unlock, streak-based acc, burn-on-loss, auto-burn), reserve economy, closed currency loop, both championships, 3 boards, final round auto-burn |
| `[Market]` | Order book, Net Worth board, defensive trading — priority 1 |
| `[Post-launch]` | Staking, idle policy, notifications, live match centre, tiebreaks, grant/basket levers, season-2 rollover, playoffs |

## 12. Deferred & Rejected

### Deferred (designed, not scheduled)

- **Staking** — passive Currency yield on un-locked tokens `[Post-launch]`. Open questions: funding source (mint vs skim vs reserve drawdown), yield formula inputs, unstake friction, market-seeding effect, dominance-vs-riding tuning. Deferred because (a) a non-TB income stream conflicts with Pillar 1, (b) funding source is unresolved in a closed loop, (c) passive yield competes with active play and may suppress jackpot-hunting.

- **Playoffs** — cascading burn war, eliminated-team freezes, wallet-burn dynamics, survivor riding. Deferred to a dedicated design session. See Open Questions.

- **Idle-policy setting** (auto-ride instead of auto-burn), **live match centre**, **full tiebreaks**, **median-scaled grant**, **basket cap** (lever if dominant teams run away), **sinks/fees beyond taker fee**, **season-2 rollover**.

### Rejected

- ~~Pre-season per-team pricing~~ — calibration risk, extra data feed; flat 1.0 start diverges through play.
- ~~Wound mechanic~~ — burn-on-loss replaces it with one uniform risk rule.
- ~~"Who Burned For Us" board~~ — merged into team-contributor board allegiance filter.
- ~~Loss fills opponent's basket~~ — great story, corrupts basket attribution.
- ~~1.0 burn floor~~ — the floor creates a +EV exploit on every crashed-team lock (mint = `(1.0 − base_at_lock) × tokens` per win). Burn-on-loss cannot neutralize this (breakeven X ≈ 78%). Without the floor, burns return exactly what was paid in — no asymmetric mint, no exploit. Underdog jackpots survive via the streak formula and token-count-as-TB on burn.
- ~~Dividend~~ — a second income stream competing with TB on the score axis; demotes burn (the scoring move) to "stake-back only" and makes Currency the primary reward of winning. Removing it simplifies the system (one fewer rule, one fewer sim lever) and keeps TB as the headline. Late-season underdog sustainability is verified by sims under the closed loop (cheap re-arming with crashed tokens).
- ~~Harvest window~~ — a 48–72h post-season trading window would let players hoard chains and dump them at full streak-bonus value, making the final window dominate the championships. Auto-burn at cutoff is simpler and keeps the season-long race as the game.

## 13. Open Questions (Post-MVP)

Deferred design problems requiring dedicated sessions. MVP ships without resolving them.

### Staking

- **Funding:** mint from common pool (breaks closed loop) · skim from active riders (taxes active play) · reserve drawdown (self-capping, ugly UX)
- **Yield formula:** single input (`base × p(win)`) vs multi-input (base, streak, standings)
- **Magnitude constraint:** yield must be < active jackpot-hunt EV on TB axis (else staking dominates) and risk-adjusted-comparable to riding on currency axis (else staking is disused)
- **Unstake friction:** cooldown rounds vs instant-sell-on-market (different mechanisms, different effects)
- **Market seeding:** stakers-as-sellers at market peaks is the mechanism by which staking supplies the seller side of defensive trading; if yield is too low to attract casuals, this effect is weak

### Playoffs and Wallet-Burn

- **Cascading burn war:** eliminated-team fans wallet-burn frozen tokens to fill their team's basket, raising the bar for surviving teams
- **Currency asymmetry:** top-team wallet-burns return more currency (high base_at_lock), funding survivor riding; underdog wallet-burns return less currency but more TB per token
- **Buy-to-burn dynamics:** fans buying own-team tokens on market to burn for basket — unbounded (whale-dominated) vs capped vs restricted to existing holdings
- **Open riding:** can eliminated fans ride surviving-team tokens, or only surviving-team fans?
- **Bar-setting:** mathematical condition under which wallet-burns vs ride-burns decide the Team Championship; sim verification required

### Alternative Registration Model

- **10 Currency + 5 tokens/team universal distribution + market-as-MVP** — shifts the game from fan-bettor to portfolio-manager identity. Different MVP scope (market required at launch). Deferred pending player-retention data from the fan-bettor MVP.
