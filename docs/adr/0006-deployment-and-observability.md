# ADR-0006 — Deployment Topology and Observability

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Launch demo runs on a single VPS (1 core, 4 GB RAM, 50 GB disk, 4 TB bandwidth) for up
to **10k active users**. 1.0 must scale to a fleet. We must choose the local ops posture
and the observability stack with those constraints in mind. User chose Docker Compose over
the native-binary recommendation; this ADR records that decision with the required
fine-print safeguards.

## Decision

### Deployment — Docker Compose, three services

- **Compose stack** (`compose.yml`): three services:
  1. `backend` — the Go binary in a **distroless / scratch + ca-certificates** image
     (~15–25 MB). Image pulled from GHCR (GitHub Container Registry). Implements
     `SIGTERM` graceful shutdown handling (finish in-flight player ops, drain SSE,
     stop deadline store, exit within `stop_grace_period`).
  2. `postgres` — official `postgres:16-alpine`, persistent named volume mounted at
     `/var/lib/postgresql/data`.
  3. `caddy` — official `caddy:2-alpine`, auto-TLS Let's Encrypt; reverse-proxies
     to `backend:8080`; serves as the public edge.
- **Resource limits** (`deploy.resources.limits`):
  - `postgres` `mem_limit: 1.5g, cpus: 0.6`
  - `caddy` `mem_limit: 128m, cpus: 0.1`
  - `backend` `mem_limit: 1.5g, cpus: 0.3`
  - ~512 MB OS headroom to absorb the periodic FinalAutoBurn sweep.
  - Numbers to be tuned after the load test described in §8 of the design doc.
- **Secrets** via Compose `secrets:` (Docker secrets), mounted read-only at
  `/run/secrets/` (`db_password`, `ed25519_player_key`, `ed25519_system_key`,
  `provider_api_key`, `otlp_token`, …). Plaintext env vars avoided (no leak via
  `ps`/`/proc`).
- **Migrations**: `golang-migrate` embedded into the backend binary itself; runs as
  part of container startup (an `init` step gated on `DB_MIGRATE=true`).
- **Restart policy**: `restart: unless-stopped`. **Stop graceful**:
  `stop_grace_period: 30s`.
- **Healthchecks** in Compose: `backend` hits its own `/readyz` (DB ping + outbox
  drain liveness), `postgres` uses `pg_isready`, `caddy` uses its built-in healthcheck
  path.
- **Backups**: scheduled Compose one-shot backup sidecar — daily `pg_dump --format=custom`
  to a local backup volume, then `rclone` push to off-site object storage (B2 or S3),
  retention 7 days (encrypted-at-rest server-side).
- **CI/CD** (GitHub Actions): build → `golangci-lint` → `govulncheck` → tests → build
  distroless multi-arch image → push to GHCR → SSH into VPS →
  `docker compose pull && docker compose up -d --remove-orphans`. Pull policy `always`;
  healthcheck gates the deploy step (`curl /readyz` retries up to 60 s).

### Observability — shift-left + off-VPS

- **Logs**: structured `slog` (text handler for dev, JSON handler for production) →
  stdout → Docker `json-file` driver with `max-size: 50m, max-file: 5` rotation.
  No log daemon on the box. Logs correlated via `trace_id` and `request_id` mapped
  from OTel context.
- **Metrics**: `prometheus/client_golang` `/metrics` on an **internal-only** port bound
  to the Compose-internal network (`expose:`, not `ports:`). Scraped from a Grafana
  Cloud Free Prometheus instance. Standard Go runtime + process metrics + custom
  counters/histograms per context (`ops_total`, `ops_duration_seconds`,
  `journal_entries_appended_total`, `deadlines_fired_total`, `outbox_lag_seconds`).
- **Traces**: OTel `otel` SDK; OTLP/gRPC exporter to Grafana Cloud Tempo free tier;
  sampling: `parentbased(trace_id_ratio=0.1)` plus always-on for any error span.
- **Health endpoints** (publicly accessible through Caddy on `/healthz` and `/readyz`):
  - `/healthz` — process alive.
  - `/readyz` — DB ping, outbox drain liveness, scheduler alive (used by Compose
    healthcheck and Caddy failover).
- **Alerting** wired later off-box via Grafana Alerting on the scrapes; out-of-scope
  for Launch minimum but documented.

## Consequences

- Positive: deterministic local + prod environment parity, isolated secrets, graceful
  shutdown, sweet-spot observability without an on-box observability cost; CI deploys
  reproducibly.
- Negative: Compose + containerd budget adds ~150 MB RAM vs a native binary; absorbed
  by the 1.5 g / 0.3 cpu backend limit; load-test required to confirm 10k user headroom
  on a 1-core box.

## Alternatives considered

- **Native binary + systemd + Caddy.** Recommended by the architect; lighter weight but
  user preferred Compose for env parity. Containerization remains a 1.0 jump-off point.
- **k3s on VPS.** Heavier orchestration than 10k players justify; rejected.
- **On-VPS Prometheus/Grafana/Loki/Tempo stack.** Rejected: ≥ 1 GB RAM footprint.
- **Vendor APM.** Free tiers cap at 10k users. Reconsider as a 1.0 candidate if cost is
  justified.

## Things kept from the original deployment recommendation

- Distroless image, golang-migrate embedded, off-site daily `pg_dump`, GitHub Actions
  CI/CD pipeline, off-VPS observability, secrets via Docker secrets (mounted files).