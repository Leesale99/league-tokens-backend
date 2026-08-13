---
description: Research an issue's approved backlog in parallel headless sandboxes
argument-hint: "<issue-number>"
---
Run the research phase for issue #$1 in headless sandboxes.

1. Confirm `docs/issue-workflows/$1/research/` contains approved briefs (`research/*/brief.md`, each with `role: <role>` on line 1). If there are no briefs yet, stop and report: the backlog-proposal and approval step needs the human and arrives in the next task.
2. Run `scripts/issue-workflow/v2/research.sh $1` — it creates `workflow.json` if absent, pre-creates one sandbox per role, dispatches every brief in parallel (at most 4 at once), collects reports, and records state + telemetry.
3. Present the gate summary from its output: per-topic state, report paths, telemetry, and the exact next command. Do not judge report quality yourself — the human reviews the reports at this gate.

The research phase is `gated` until the human approves; never re-dispatch a `gated`/`done` phase.
