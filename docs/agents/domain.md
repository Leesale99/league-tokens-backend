# Domain Docs

How agents should consume this repo's domain documentation.

## Reading order — ADRs first, specs last resort

Do NOT load the big spec documents upfront. Follow this order:

1. **`CONTEXT.md`** at repo root — glossary + ADR index. Always load this first.
2. **`docs/adr/`** — read only the ADRs relevant to your task. Use the index in CONTEXT.md to pick the right ones.
3. **`specs/game_engine_spec.md`**, **`specs/game_design.md`**, **`specs/backend_system_design.md`** — read ONLY if an ADR doesn't cover your question. These are large documents; avoid loading them unless you need engine formulas, game design intent, or cross-cutting architecture detail not in any ADR.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── CONTEXT.md                            ← primary context (load first)
├── docs/
│   ├── agents/
│   │   ├── domain.md
│   │   ├── issue-tracker.md
│   │   └── triage-labels.md
│   └── adr/
│       ├── 0001-bounded-contexts.md
│       ├── … through …
│       └── 0012-configuration.md
├── specs/
│   ├── glossary.md                       ← ubiquitous language (authoritative source)
│   ├── game_design.md                    ← game design intent (last resort)
│   ├── game_engine_spec.md               ← authoritative engine behaviour (last resort)
│   └── backend_system_design.md          ← backend architecture (last resort)
└── internal/                             ← implementation
```

## Use the glossary's vocabulary

When your output names a domain concept, use the term as defined in `CONTEXT.md` (sourced from `specs/glossary.md`). Don't drift to synonyms.

If the concept you need isn't in the glossary, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (security posture) — but worth reopening because…_
