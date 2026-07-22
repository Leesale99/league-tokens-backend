# ADR-0010 — Fixed-Point Money Type (`shopspring/decimal`, precision-locked)

Status: Accepted
Date: 2026-07-22
Deciders: backend architect, product owner

## Context

Spec §6.12 mandates fixed-point six-decimal token math, with persisted arithmetic
rounded to **6 decimals, round-half-up** at **every write boundary** (`UpdateBase`,
`AccDelta` accrual, burn payout, reserve-buy price, loss-destruction). The earlier
"floor at loss-destruction only" rule was superseded (see the spec's `Conventions`
note and §6.12). §6.12 is a **security invariant** — inconsistent rounding silently
breaks game economics — so the helper, its rounding discipline, and its storage shape
all become first-class design decisions.

## Decision

Use **`github.com/shopspring/decimal`** with the project-wide discipline below. (Architect
had recommended an int64/1e-6 helper; the user chose `decimal` for clarity and precision
headroom; both decisions reachable. The discipline below keeps §6.12 invariant regardless
of helper choice.)

### Module location

`internal/infra/money` is the **only** package allowed to perform arithmetic on money
amounts. It re-exports the typed `Amount`, `Tokens`, `Odds` aliases over
`decimal.Decimal` and exposes only the operations the spec uses. Every operation
ending in a persisted value applies `.Round(6)` once (round-half-up, the `decimal`
default once `decimal.DivisionPrecision = 6`):

- `Add`, `Sub` — checked to refuse negative results when labelled as a balance-debit;
  exact at 6 dp (inputs are already 6 dp so no rounding needed).
- `MulByDecimal(amount, factor)` — `.Round(6)` on the result.
- `MulByInt(amount, n)` — exact (integer multiply preserves scale).
- `MulCurrency(base, tokens)` — `(base × tokens).Round(6)` — spec §5.3 burn payout
  + §5.5 reserve-buy price.
- `UpdateBase(base, mult)` — `(base × mult).Round(6)` — spec §5.4.
- `AccDelta(tokens, odds, streak, s)` — exactly §5.1, then `.Round(6)`. The feed
  contract says `odds` enters at up to 6 dp; `streak` is int; `s` is a per-season
  constant. If for some reason the subexpression has more than 6 decimal places,
  the helper rounds it to 6 (half-up) — there is no longer an `ErrTooMuchPrecision`
  *error* path here, only the disciplined round; we keep the overflow check separate
  (values outside sane bounds reject).
- `LossDestroy(tokens, X)` — `(tokens × X).Round(6)`, plus `returned = tokens −
  destroyed`. **The previous `.Floor()` rule is gone**; loss-destruction now uses the
  same round-half-up as everywhere else (per spec §5.2/§6.12 update).

### Rounding discipline

- `decimal.DivisionPrecision` set globally to **6**.
- All persisted arithmetic functions defined above apply `.Round(6)` exactly once,
  inside `internal/infra/money`.
- `.Div(...)`, `.RoundUp`, `.RoundDown`, `.Floor`, `.Truncate` calls are **banned** in
  `internal/infra/money`. We use only `.Round(6)` (round-half-up, the `decimal` default
  after `decimal.DivisionPrecision = 6`).
- Lint rule (depguard + ruleguard pattern) bans any `.Round`/`.RoundUp`/`.RoundDown`/
  `.Floor`/`.Truncate`/`.Div` call anywhere outside `internal/infra/money` and bans
  everything except `.Round(6)` inside `internal/infra/money`.

### Precision verification (test contract)

- Property test: every `Amount`/`Tokens`/`Odds` returned by a `money` function has
  `.Exponent() ≥ -6` (i.e. fits in six decimal places). Anything else fails the build.
- Property test: `LossDestroy(t, X).destroyed + .returned == t` (exact), and
  `destroyed == decimal.Require(t.Mul(X)).Round(6)`.
- Property test: `AccDelta(...)`'s subexpression `(odds-1)*(1+streak*s)` is swept over
  `streak ∈ [0,10]`, `s ∈ {0.1, 0.2, 0.4}`, `odds ∈ [1.0, 9.0]`; the stored result equals
  `Round(6)` (round-half-up) of the exact real number, by re-computing with arbitrary-
  precision rationals and asserting equality.
- Property test for `MulCurrency` and `UpdateBase`: the stored value equals
  `Round(6)(base × tokens, base × mult)` against an arbitrary-precision source.
- Overflow guard test: a documented sanity ceiling (per `money.Config.MaxBalance`,
  set well above engine cap) rejects any single balance that would exceed it; catches a
  misconfigured constant early.

### Storage

- Postgres column type for monetary balances: **`NUMERIC(38, 6)`** (38 digits, 6 after
  the decimal point). `NUMERIC(38, 6)` accepts only 6-decimal values; values with extra
  precision are rounded **by Postgres's own NUMERIC rounding** at the column scale on
  insert. Postgres's NUMERIC rounding is its own policy, so we **never** depend on it —
  the application is the rounding authority (every persisted arithmetic step is
  `.Round(6)` before write). A project-level property test asserts that for every
  stored value, `stored == decimal.Decimal(s.InMemory).Round(6)` holds — i.e. what we
  wrote is exactly what we computed, not re-rounded by Postgres.
- `money.Odds` column type is `NUMERIC(8, 6)` (odds rarely exceed `99.000000`).

### JSON serialization

- `money.Amount.MarshalJSON` returns the value as a string in fixed six-decimal
  format (always six digits after the dot, e.g. `"50.000000"`, `"2.500000"`,
  `"0.250000"`). Frontends parse a constant shape.
- `decimal.Decimal`'s default JSON would emit `"50"` then `"50.5"` then `"50.500000"`
  depending on value — that inconsistency breaks weakly-typed client json parsers, so
  the custom marshaler is mandatory.

### Feed entry contract

- The feed adapter Parses provider payloads into `money.Odds` using
  `decimal.NewFromString`. If the upstream `odds` payload carries more than 6 decimal
  places it is `.Round(6)` before persistence (per the §6.12 discipline, same as every
  other persisted arithmetic step); the engine never sees anything outside 6 dp.

## Consequences

- Positive: §6.12 invariant held by code + storage + tests + lint; consistent client
  shape; arbitrary precision headroom for the eventual `[Market]` addendum if it
  requires higher precision.
- Negative: decimal exceeds int allocation cost; final-FinalAutoBurn sweep of 10k rides
  is still a single-digit-ms total — non-issue. Larger dep than a hand-written int64
  helper but routine.

## Alternatives considered

- **Keep `floor` at loss-destruction only (the prior spec rule).** Rejected per the
  spec update: rounding every persisted arithmetic step is consistent and removes the
  silent rounding that Postgres would otherwise apply at base accumulation.
- **Hand-rolled `int64` + 1e-6 unit helper.** Architect recommendation; lower alloc,
  fewer deps; tight enough for §6.12. Rejected in favour of decimal for clarity and
  precision headroom; the discipline above keeps both choices equivalent on security.
- **`float64`**. Rejected: floats break §6.12.
- **No helper (`int64` + free arithmetic).** Rejected: security invariant cannot be
  enforced without a closed API.