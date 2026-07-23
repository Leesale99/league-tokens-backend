# ADR-0009 — 1.0 Scaling Strategy (Modular Monolith → Microservices, staged)

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

The Launch demo runs as a single Go binary in Docker Compose on one VPS for 10k
active users (ADR-0006). The 1.0 product must scale to a much larger fleet. The
requirement is to grow the monolith **into** microservices, not replatform. Each stage
must hold working code and traffic — no big-bang rewrites.

The seams that make this possible were deliberately carved at Launch: consumer-owns-port
(ADR-0008), Game↔Ledger sync seam with the async flip available on demand (ADR-0002),
outbox on every money-mutating op (ADR-0002), system-only token authority (ADR-0004),
and per-context SQL schemas (ADR-0002/0008).

## Decision — six staged extraction checkpoints

### Stage 1 — Read path (decoupling reads from money writes)

- Cloudflare edge cache for **read-only public** reads (`/v1/boards/*`,
  `/v1/season/*` GET).
- PostgreSQL **read replica** + **PgBouncer** pooling for read traffic.
- **Redis cache** fed by explicit outbox-driven invalidation rules (cache-aside). This
  is the first time Redis appears; it remains optional and cache-only at this stage.
- **Extract `rankings`**: stateless projection service running 2..n replicas; reads
  from its own replicated database table set.
- First horizontal backend replica on the edge (still the Launch monolith shaped
  binary); Cloudflare round-robins.

### Stage 2 — Event backbone (cross-process event transport)

- Add a managed **event backbone**: **Kafka** or **NATS JetStream** (operational
  simplicity preferred at this scale — NATS JetStream is sufficient and lighter ops).
- The **outbox relay** that today feeds in-process channels now publishes to the
  backbone; downstream contexts (`rankings`, `market`, audit, notifications) consume
  over the wire. No behavior change — only the transport changes.
- At-least-once delivery with idempotent consumers keyed on outbox `event_id` (already
  present at Launch).

### Stage 3 — Extract `ledger` (flip Game↔Ledger to async)

- `ledger` moves to its own Postgres instance (specialist IOPS profile, isolated write
  latencies — money writes should not be throttled by read traffic).
- ADR-0002's documented seam kicks in: Game↔Ledger flips from the in-process sync
  function call to **async commands** over the backbone. Commands keyed by `user_id` to
  preserve per-account ordering; idempotency via the existing `idempotency` table
  (ADR-0003); correlation IDs return accept/reject on a reply topic that the issuing
  `game` instance consumes.
- Player mutating ops now return "pending" only when they're player-initiated and
  **expected** to wait on a backend to ack; the UX guidance is documented per op in
  the design doc. Most still complete in <100 ms over NATS JetStream on the same VPC.

### Stage 4 — Extract `game` (shard by season)

- Multiple `game` instances partitioned by `season_id`; **single-writer-per-season**
  preserves engine invariants (§2.4 FinalAutoBurn across-the-league sweep is in-process
  again).
- `ResolveMatch` ordering preserved by backbone partition key = `match_id`; a single
  Kafka partition consumer processes each match's settle cascade in order.
- One game instance owns each season; seasons are not automatically routed across
  instances; the schedule service routes `ResultAvailable` events to the correct
  instance via `season_id` partition key.

### Stage 5 — SSE fan-out horizontal

- SSE channels move to **Redis Pub/Sub** (or NATS JetStream subjects); the long-lived
  HTTP/SSE connection per player stays open with whichever backend they hit, but events
  **fan out from any backend to all backends** via the shared pub/sub layer.
- LB no longer needs sticky-by-subject; any backend can serve any subscription.
- Cloudflare in front of SSE bypassing cache (verified pre-Launch). SSE subscription
  cap per backend instance enforced (per ADR-0007).

### Stage 6 — Migration to managed compute + K8s + multi-AZ

- Migrate to managed Kubernetes (DigitalOcean LKE / GKE / EKS) for autoscaling.
- **Multi-AZ managed Postgres** (RDS / Cloud SQL / Crunchy Bridge) with PITR and
  automatic failover.
- **Blue/green** per-context deployments; canary per-context; status-aware LB.
- Cloudflare managed **WAF** replaces the Launch free-tier ruleset.
- External **IdP** (Ory Kratos or Authentik) if MFA / social login is required.
- **WebAuthn** as a passwordless upgrade.

## Trigger conditions (engineering, not calendar)

Stages engaged by observable thresholds, not time:

- Stage 1 when backend CPU **sustainably > 65%** over 5 min or DB read load queues.
- Stage 2 when a third downstream context of the journal needs event delivery or the
  outbox backlog grows beyond 1 s lag under normal load.
- Stage 3 when ledger write latency falls behind 50 ms p99 under peak round-resolution
  burst.
- Stage 4 when a single `game` CPU saturates at peak (`ResolveMatch` cascades grow with
  active seasons).
- Stage 5 when SSE connection count per backend crosses the per-instance budget.
- Stage 6 when multi-AZ resilience and autoscaling outcompete the VPS footprint on cost.

## Consequences

- Positive: every stage is independently deployable and holds traffic; Launch seams carry
  the design directly into microservices; no domain rewrite at any stage; correctness
  preserved by Kafka partitioning, per-account ordering, and single-writer-per-season.
- Negative: each stage introduces an infra component (Redis, broker, multi-AZ DB); teams
  acquire Ops/SRE responsibilities; the "pending" UX at Stage 3 needs product sign-off.

## Alternatives considered

- **Microservices from day one.** Premature distribution; rejected for risk/cost vs the
  Launch demo's stated mission.
- **Vertical scaling only.** Stage 1.5 tactical stop-gap; not the destination.
- **Shard `ledger` by `player_id` directly.** Premature; extract contexts before
  sharding.