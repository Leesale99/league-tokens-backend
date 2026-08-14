---
description: Research phase — backlog gate, parallel sandbox dispatch, context synthesis
argument-hint: "<issue-number>"
---
Run the research phase for issue #$1 in headless sandboxes. Three stages, each ending in a human gate. You orchestrate and present gates only — you do not research, judge report quality, or edit artifacts.

## Stage 1 — propose the research backlog (gate: human approval)

0. Resolve the run dir: `RUN_DIR=$(scripts/issue-workflow/v2/run_dir.sh $1)` — it lives outside the repo; use it for every path below.
1. Read `$RUN_DIR/issue.md`.
2. If `research/` already contains approved briefs, skip to Stage 2.
3. Propose a backlog of research todos covering, where applicable: existing code and tests, package/module seams, ADRs, specs, git history and conventions, knowledge-base prior art (vault), database/schema/migrations, API contracts, dependency versions and current documentation, operational/security constraints, design alternatives, compatibility, edge cases, failure modes, and acceptance-criteria gaps. Challenge the issue: ambiguity, unstated assumptions, missing acceptance criteria, possible scope changes.
4. Each todo has an ordering-prefixed slug `<NN>-<slug>`, one research role (`repo-researcher`, `docs-researcher`, `web-researcher`, `kb-researcher`), and the exact question. Present the table and discuss until the human explicitly approves it.
5. On approval, write one brief per todo at `research/<NN>-<slug>/brief.md`: **line 1 is `role: <role>`**, then the question, scope, expected sources, deliverables, constraints, and report format — self-contained for a headless agent.

## Stage 2 — dispatch in parallel

Run `scripts/issue-workflow/v2/research.sh $1` (creates `workflow.json` if absent, pre-creates one sandbox per role, dispatches at most 4 briefs in parallel, collects reports, phase → gated). Present its summary table. If any agent `failed`, do **not** synthesize: offer `research.sh $1 --redispatch` after the human amends the failed briefs, and wait.

## Stage 3 — synthesize context.md (gate: human approval)

1. Write `$RUN_DIR/synthesis-brief.md` pointing at the reports and the `context-synthesizer` role contract.
2. Dispatch `scripts/issue-workflow/v2/dispatch.sh $1 context-synthesizer $RUN_DIR/synthesis-brief.md`.
3. Present `context.md` (its TL;DR for humans, contradictions, and open questions) for human approval.
4. On approval, run `scripts/issue-workflow/v2/research.sh $1 --finalize` and report `next: /issue-plan $1`.
