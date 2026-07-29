## Agent skills

### Issue tracker

Issues and PRDs for this repo live as GitHub issues (uses the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles kept as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Do NOT load the big spec documents upfront. Follow this order:

1. **`CONTEXT.md`** at repo root — glossary + ADR index. Always load this first.
2. **`docs/adr/`** — read only the ADRs relevant to your task. Use the index in CONTEXT.md to pick the right ones.
3. **`specs/game_engine_spec.md`**, **`specs/game_design.md`**, **`specs/backend_system_design.md`** — read ONLY if an ADR doesn't cover your question. These are large documents; avoid loading them unless you need engine formulas, game design intent, or cross-cutting architecture detail not in any ADR.

See `docs/agents/domain.md`.
