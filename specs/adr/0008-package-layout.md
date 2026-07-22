# ADR-0008 — Go Module and Package Layout (Modular Monolith, DDD + Hexagonal)

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

We have settled seven bounded contexts (ADR-0001) and the Game↔Ledger port/adapter
shape (ADR-0002). We need a Go package layout that keeps contexts from importing each
other directly while letting `cmd/server/main.go` do all wiring — so a context can be
extracted to its own process at 1.0 by re-pointing one port.

## Decision — consumer-owns-port; events in shared kernel

- One Go module at the repo root.
- Context packages: `internal/identity`, `internal/schedule`, `internal/game`,
  `internal/ledger`, `internal/rankings`, `internal/market`.
- Each context directory has:
  - `domain/`           entities, value objects, aggregates, invariants, domain errors.
                        No I/O, no imports of other contexts.
  - `application/`      ports (Go interfaces) owned by the consumer + use-case command
                        and query handlers. This is where a context declares what it
                        needs from others.
  - `adapter/`
    - `postgres/`       repositories generated/typed via `sqlc`.
    - `http/`           HTTP presenters + handlers bound by `internal/http` to the
                        router; renders `application/problem+json`.
    - `outbox/`         implementation of the shared outbox writer port.
  - For producer contexts, concrete implementations of *another context's* port live
    here too (e.g. `internal/ledger/adapter/gameclient` implements
    `game.application.LedgerPort`).
- `internal/feed/` is an adapter-only package — a stateless HTTP client of the upstream
  provider. It writes results through the `schedule` port; it owns no state itself.
- `internal/infra/` is the shared kernel:
  - `bus/`        in-process pub/sub (Go channels) + outbox relay
  - `scheduler/`  deadline store + `time.AfterFunc` (ADR-0005)
  - `telemetry/`  slog JSON, OTel, Prometheus wiring
  - `db/`         `sqlc`-generated code, **one fileset per context schema** (preserves
                  a clean seam for 1.0 per-context DB extraction)
  - `money/`      `int64` fixed-point 1e-6 helper (ADR-0009)
  - `events/`     shared event schemas (`BurnOccurred`, `ResultAvailable`,
                  `CutoffFired`, `MatchResolved`, `ReserveBuyOccurred`, …). Outbox rows
                  carry `type` + JSON payload; consumers filter on `type`.
- `internal/http/` is the edge — router, middlewares, SSE broker, problem+json mapper.
- `migrations/`  — one golang-migrate SQL fileset per context schema
  (`migrations/identity/`, `migrations/ledger/`, …).
- `api/openapi.yaml` — the player-edge contract doc; `.proto` directory reserved for
  1.0 internal gRPC seames.
- `compose.yml`, `Caddyfile`, `Dockerfile`, `.github/workflows/`.

### Naming choice rationale

- `domain/application/adapter` over `model/ports/adapters`: `application` matches
  Hexagonal/Clean Architecture literature for the use-case layer; `ports` is implicit
  in `application` because the Go interfaces in `application/ports.go` are the ports.
- Reviewer note: if a future PR prefers `ports/adapters` for clarity we can rename
  without changing semantics; not worth touching initially.

### Cross-context collaboration rules

- A context NEVER imports another context's package. Didier ports defined in the
  consumer's `application/` package; `cmd/server/main.go` is the **only** file that
  imports both producer adapters and consumer application services.
- `internal/infra` is freely importable by every context; it is the shared kernel.
- Outbox event types are **structural-only**, defined once in `internal/infra/events`.
  ADR-0003 outbox rows are serialized as JSON matching these typed structs; producers
  emit, consumers annotate-only.

## Consequences

- Positive: cleanest possible seam for 1.0 extraction (edit `main.go` to swap a
  function call adapter for a gRPC adapter implementing the same port). Contexts are
  independently testable — fakes impl consumer ports trivially. Compile-time proof
  that no context reaches into another.
- Negative: requires discipline to keep `main.go` lightweight; some violation gorillas
  will propose "just one helper". Mitigated by an import-cycle linter
  (`depguard` rule in golangci-lint) banning cross-context imports outside `main`.

## Alternatives considered

- **Producer exports the interface.** Faster setup, breaks strict hexagonal, complicates
  1.0 extraction; rejected.
- **Per-context event packages.** Reintroduces cross-context imports; deleted.
- **Clean/Onion naming (`core/usecase/infrastructure`).** Cosmetically fine; same shape;
  we picked `domain/application/adapter`.