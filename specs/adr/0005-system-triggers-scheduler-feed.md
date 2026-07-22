# ADR-0005 — System Triggers, Scheduler, and Feed Ingestion

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

The engine spec defines three system-only triggers:

- `ResolveMatch(match)` — when the feed delivers a result (§3).
- `AutoBurnDeadline(round)` — when the round's cutoff `scheduled_first_tipoff(round) − 1h`
  fires (§3, §6.1).
- `FinalAutoBurn` — when the last match of round R resolves; league-wide sweep of every
  `WonPending` ride (§2.4).

These must be restart-safe, at-most-once, and require no external job broker at Launch.
Additionally the feed ingestion style needs to be settled before the `feed` adapter is
designed.

## Decision

### Feed ingestion — pull/poll primary, webhook optional

- `feed` adapter **pulls** the upstream provider (default interval 30 s, exponential
  backoff on errors, provider-key passed via env). Only `feed` writes into the
  `schedule` context.
- Writes are idempotent on `(match_id, provider, payload_hash)`.
- On a new match result, `schedule` emits `ResultAvailable` on the outbox; `game`
  consumes and runs `ResolveMatch`.
- Optional authenticated webhook endpoint at `/v1/internal/feed/events/<provider>`
  enables push delivery later (HMAC-verified) without changing downstream contracts.

### Timed triggers — Postgres-backed deadline store inside `infra.scheduler`

- Half source of truth: `infra.deadlines` table with columns
  `(kind, ref_id, fire_at, fired_at, created_at)`.
- Recompute rule: every time `schedule.match` rows change, the scheduler recomputes
  `round_cutoff = min(match_scheduled_tipoff round=…) − 1h` and upserts / deactivates
  the matching deadline.
- On boot, the scheduler loads **all unfired** deadlines and registers each with
  `time.AfterFunc(fire_at − now, fire)`. Firing:
  1. Begins a tx.
  2. `UPDATE ... SET fired_at=now() WHERE fired_at IS NULL RETURNING` — at-most-once.
  3. If it won the update, appends a `CutoffFired(ref_id)` outbox event.
  4. Commits.
- `game` consumes `CutoffFired` and runs `AutoBurnDeadline(round)` — for every
  `WonPending` ride whose action window closes at that round's cutoff, burn it
  (§4.3 burn mechanics), emitting `BurnOccurred` events.
- Restart drift: a deadline whose `fire_at` was missed while the process was down is
  fired **immediately** at boot, with a single guarded "catchup" tick.

### FinalAutoBurn — cascade inside ResolveMatch, batched

- `FinalAutoBurn` is **not** a separate timed trigger. When `ResolveMatch` for the
  last match of round R commits inside one Postgres transaction:
  - Update bases for that match's teams.
  - Settle the locked rides of that match (win/loss per §3.1).
  - Then sweep every `WonPending` ride league-wide and burn each. The sweep is
    **batched at 1k rides per inner batch** to bound lock time and lock contention
    inside the same logical transaction, committing each batch as a separate
    Postgres transaction (the sweep idempotency key is `(round, ride_id)`; a crash
    resume re-reads remaining `WonPending` rides and resumes).
- For the 10k-user Launch demo this is well within the 1-core box's capacity.

### Auth on system ops

- All system triggers run with the **`system` token** (ADR-0004). The scheduler and the
  `feed` consumer are the only minters of `system`-scoped tokens; player tokens cannot
  cause `AutoBurnDeadline`, `FinalAutoBurn` or `ResolveMatch`.

## Consequences

- Positive: zero external job broker needed at Launch; restart-safe; at-most-once
  firing; well-defined backlog handling; feed cadence architecture is provider-agnostic.
- Negative: a missed deadline is caught up only once the process boots — we accept
  "no engine ticks under downtime" since match results are pulled anyway and
  re-pulled on recovery.

## Alternatives considered

- **Webhook-push only.** Rejected: locks provider choice.
- **External scheduler (Temporal / cron / Airbyte).** Rejected at Launch: broker ops
  burden on the 1-core box; Redis/Temerbridge quota not justified.
- **`time.Sleep` loop.** Rejected: jitter, hard reasoning about missed deadlines.
- **FinalAutoBurn as a separate timed deadline.** Rejected: pointless extra trigger;
  cascading on the `MatchResolved` event is provably equivalent and atomic.