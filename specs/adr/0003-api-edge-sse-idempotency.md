# ADR-0003 — Public API Edge, Real-time Channel, and Idempotency

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Players need a public API. Real-time server→client traffic is **low-frequency** — a
handful of events per real-world round (boards reshuffle, cutoff clock, match-resolved,
command-completion ack). It is not bidirectional chat. Players will double-click "Lock"
/ "Burn". Spec §3.2 already specifies an `AlreadyResolved` idempotency pattern for
`ResolveMatch`; we extend the same discipline to player mutating ops.

## Decision

- **Public edge = HTTP/1.1 + REST/JSON.** Commands are POST/PUT/DELETE; reads are GET.
  JSON bodies; standard HTTP status semantics; typed application/problem+json errors.
- **Server-Sent Events (SSE)** for the one-way server→client stream:
  `/v1/events?topics=...`. Carries board reshuffles, cutoff-clock ticks, match-resolved
  notifications, command-completion acks (correlated by idempotency key).
- **Idempotency-Key** header on every mutating command. Backend stores
  `(subject_id, idempotency_key) → (command_hash, response, expires_at)` for at least
  24 hours; a re-submit with the same key returns the **stored response** verbatim.
  This mirrors spec §3.2 `AlreadyResolved` on the player side.
- **gRPC stays internal-only** at Launch (not exposed). Backend ↔ client is REST only.
  gRPC may be adopted as the **1.0 service-to-service** wire once contexts split into
  separate processes — kept off the edge for client universality at Launch.
- **TLS termination**: a single reverse proxy (Caddy or Nginx) in front of the Go
  binary terminates TLS, sets HSTS, forwards plain HTTP to the backend on localhost.
- **Edge security headers** enforced at the proxy + Go middleware:
  `Content-Type: application/problem+json` for errors, `Strict-Transport-Security`,
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `Cache-Control: no-store` on mutating endpoints and SSE.
- **Rate limiting** at the proxy per-IP and per-JWT-subject (token-bucket); see
  ADR-0005 (security).

## Rationale

- SSE is HTTP — proxies, LBs and the 4 TB budget handle it natively, no sticky sessions,
  no WS upgrade dance, trivial reconnect with `Last-Event-ID` for replay.
- WebSocket's bidirectionality buys us nothing (player commands go through REST) and
  costs sticky sessions and bespoke replay logic at 1.0.
- Polling wastes bandwidth and lags UX exactly on the events players care about
  (round resolution).
- gRPC-Web at Launch buys unified types across clients, but Launch has one web client;
  the typing cost over REST isn't worth paying until a multi-platform 1.0 client fleet
  exists.

## Consequences

- Positive: trivial infra (one Go binary, one proxy), idempotent re-submits, free
  Last-Event-ID replay, zero sticky-session requirement, portable later.
- Negative: SSE has one connection per client; for 10k concurrent SSE subscribers
  Postgres + one Go process is fine (SSE is long-lived idle HTTP), but we will guard
  connection counts at the proxy with `Caddy` defaults and verify in load tests.

## Alternatives considered

- **WebSocket full-duplex.** Rejected: overkill for one-way low-frequency events,
  heavier client, sticky-session infra.
- **REST + polling.** Rejected: wastes the bandwidth budget; laggy UX.
- **gRPC-Web on edge at Launch.** Rejected: premature multi-platform optimization;
  deferred to 1.0 client-platform call.

## Idempotency-key storage (referenced from ADR-0002)

```
CREATE TABLE infra.idempotency (
  subject_id    bigint  NOT NULL,
  key           text    NOT NULL,
  command_hash  bytea   NOT NULL,   -- sha256 of (method+path+canonical body)
  response      jsonb,              -- the body returned on first attempt
  status        int,
  expires_at    timestamptz NOT NULL,
  PRIMARY KEY (subject_id, key)
);
```

Stored inside the same in-process Postgres transaction as the command it guards; a
collision on `(subject_id, key)` with a matching `command_hash` returns the saved
response, with a mismatching `command_hash` returns `409 Conflict`.