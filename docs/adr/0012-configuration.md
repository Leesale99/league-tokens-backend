# ADR-0012 — Configuration Management

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Each context needs config (DB DSN, signing keys, provider URL, rate limits, etc.).
Docker Compose supplies environment + Docker secrets (files at `/run/secrets/`).
Per ADR-0006/0007 secrets are never committed, never in plain env vars exposed via
`ps`/`/proc`.

## Decision

- **12-factor env-driven config** for non-secret parameters.
- **Docker secrets** resolve to files at `/run/secrets/<name>`; a tiny
  `secretsfile` helper in `internal/infra/config` slurps each into the typed
  Config struct on startup. Never logged, never echoed back via API.
- Typed `Config` struct per context in `internal/<ctx>/application/config.go`
  (typed only inside the context — the context owns its config; no global
  `Config` god-object).
- Parsed via **`github.com/caarlos0/env/v11`** — struct-tag based, lightweight,
  zero tree-of-hierarchies mental model.
- Shared kernel provides a **base** typed struct: `infra.Config` for telemetry
  (OTLP endpoint + token), DB DSN, server listen address, log level.

### Validation

- `Config.Validate()` method on every context's Config; runs in
  `cmd/server/main.go` *before* any subsystem starts.
- Invalid config → `log.Fatal` with a structured message; process exits 1.
  This is the single allowed panic-equivalent: serving traffic with bad config
  is worse than refusing to start.

### Hot reload

- **None at Launch**. Restart for updates. Compose `docker compose up -d`
  rotates the binary with graceful shutdown (ADR-0006); kill `-HUP` is not
  supported.

### Files

- No `.env` files in the repo (never committed).
- `compose.env.example` checked in (keys only, no values) to document the schema.
- `secrets/` directory is runtime-only on the host; never created in the repo.

## Consequences

- Positive: 12-factor portability, no viper tree, per-context isolation, secrets
  isolation, fast-fail on misconfig.
- Negative: restart-required for config changes — accepted at Launch.

## Alternatives considered

- **spf13/viper with YAML+env+secrets**. Rejected: layered precedence and provider
  tree add unnecessary mental model at Launch.
- **Hand-rolled `os.Getenv` checks**. Rejected: brittle type coercion and
  required-field validation under a Secure-by-Design product.
- **Repo `.env` files**. Rejected: high leakage risk under Secure-by-Design.