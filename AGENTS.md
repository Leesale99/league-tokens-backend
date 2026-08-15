## Agent skills

### Issue tracker

Issues and PRDs for this repo live as GitHub issues (uses the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles kept as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Do NOT load the big spec documents upfront. Follow this order:

1. **`CONTEXT.md`** at repo root — glossary + ADR index. Always load this first.
2. **`docs/adr/`** — read only the ADRs relevant to your task. Use the index in CONTEXT.md to pick the right ones.
3. **`docs/specs/game_engine_spec.md`**, **`docs/specs/game_design.md`**, **`docs/specs/backend_system_design.md`** — read ONLY if an ADR doesn't cover your question. These are large documents; avoid loading them unless you need engine formulas, game design intent, or cross-cutting architecture detail not in any ADR.

See `docs/agents/domain.md`.

### Knowledge base

Project memory (decision log, lessons, closed-issue archive) lives in the `league-tokens` Obsidian vault. Search it for past-work questions and prior art, never for current system state. See `docs/agents/knowledge-base.md`.

### Tool use norms

- Library/API questions (any library, even familiar ones): **context7 first** — `resolve-library-id` → `query-docs` (≤3 calls). Do not curl raw source for documentation.
- General research: `web_search` (2–4 varied queries). Claim verification: `source_check`. Raw `curl`/`fetch_content` only when a pinned source line or exact HTTP body is needed and context7/web_search cannot provide it.
- After any non-obvious tool choice, say in one line why — so the norm is self-enforcing and reviewable.
