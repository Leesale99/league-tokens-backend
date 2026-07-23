# ADR-0002 — Persistence, Consistency, and the Game↔Ledger Command Flow

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner
Supersedes: —
Superseded by: —

## Context

ADR-0001 settled the bounded contexts and named `Ledger` the sole money authority with
an intent-command contract. This ADR decides:

1. What storage backs each context for the Launch demo (1 core / 4 GB / 50 GB VPS,
   10k active users, modular monolith), and the 1.0 split path.
2. How Game↔Ledger *commands* flow at Launch — synchronous in-process calls vs async
   event commands.
3. The persistence shape — mutable snapshots vs full event sourcing.

The two axes are independent and were unbundled from the discussion:

- **Axis A — persistence shape:** snapshot+audit-appender (hybrid) vs full event
  sourcing.
- **Axis B — Game↔Ledger command flow:** synchronous in-process call vs asynchronous
  event commands.

## Decision

### 1. Storage

- Single RDBMS for Launch: **PostgreSQL**. One logical **schema per context**
  (`identity`, `schedule`, `game`, `ledger`, `rankings`, `market`, `infra`), accessed
  only via that context's own port/adapter (hexagonal). The 1.0 split is re-pointing
  adapters, not a rewrite.
- **Ledger** is a **double-entry append-only `journal_entries` table** plus a
  **materialized `balances`** table (rebuildable from the journal). The journal *is*
  the source of truth; balances is a projection.
- **Game** Ride aggregate is a **mutable snapshot** (`rides` table) with an optimistic
  `version` column (Etag), plus a **`ride_events` appender** for audit. Not full event
  sourcing at Launch.
- No Redis / Kafka / external broker at Launch. Cross-context async messaging uses an
  **in-process event bus (Go channels)** backed by a Postgres **outbox table**, written
  inside the producing transaction (transactional outbox).
- Sessions: stateless JWT in cookies (short-lived) + refresh tokens. No session store
  needed (no Redis). See ADR-0005 (auth).

### 2. Game↔Ledger command flow at Launch → **synchronous, in-process, single transaction.**

- A player op (`Lock`, `Burn`, `ReserveBuy`, `Ride`) executes as **one Postgres
  transaction** spanning Game and Ledger: Game calls `Ledger.Acquire(...)` as an in-process
  function call; the ledger appends journal entries and updates balances; Game mutates
  the Ride; both commit (or roll back) atomically.
- After commit, both contexts **emit events into the outbox table** (within the same txn)
  for async delivery to downstream consumers (Rankings, Market, audit, notifications). See
  ADR-0003 for the outbox pseudocode.

### 3. Hybrid persistence (NOT full event sourcing at Launch)

- Ledger is event-shaped by accounting convention (append-only journal).
- Ride / Player-season / Season / Round are mutable snapshots with event-appenders for
  audit, not event-sourced aggregates.
- Full event sourcing for `game` aggregates is a **1.0 candidate** (evaluated when the
  `game` process is split out), not a Launch requirement.

## Rationale

- On a 1-core / 4 GB box with both Game and Ledger in the same binary, async event
  commands between them are the **premature-distribution** antipattern: no network to
  be async over, all cost (idempotency keys, correlation IDs, timeout reconciliation,
  reject-and-undo, pending player UX) and no benefit.
- Synchronous + one txn gives the player an atomic OK and rides Postgres' isolation
  levels for correctness — at 10k users the ~200 RPS peak is comfortably within Postgres'
  budget on the demo box.
- The outbox seam preserves the 1.0 path: extracting a context means replacing one port
  with an async command at a real process boundary; downstream consumers do not change.

## Consequences

- Positive: atomic player-op semantics, free audit (journal + ride_events), one moving
  part, trivial deploy, clean evolution to async / event sourcing / microservices.
- Negative: Game and Ledger must scale together until the 1.0 seam swap; the hybrid
  persistence (snapshot + ride_events) means reconstruction-by-replay is only available
  for the audit trail, not for live state — acceptable, the snapshot is authoritative.

## Alternatives considered

- **Full event sourcing + async at Launch.** Rejected: cleaner replay/audit but
  premature tooling for a one-engineer MVP; the outbox already buys the replay-able
  journal for the most audit-sensitive context (Ledger).
- **SQLite WAL for demo.** Rejected: zero-ops benefit but a disruptive storage swap
  at 1.0, weaker concurrency story.
- **Redis for sessions / rankings cache at Launch.** Rejected: extra moving part on a
  1-core box; Postgres handles the read load. Reconsider at 1.0 as read replicas +
  cache tier.
- **Async event commands between Game and Ledger at Launch.** Rejected: premature
  distribution; preserved as the 1.0 evolution path via port redirection.