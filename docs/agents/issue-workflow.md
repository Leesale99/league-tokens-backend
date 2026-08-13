# Issue workflow

This repository uses project-local Pi prompt templates for the issue lifecycle.
Commands follow the `<domain>-<verb>` convention: `/issue-*` are the human
lifecycle commands; roles are contract files, not commands.

## Workflow

1. `/issue-start [issue-number]` selects a Ready board item (or asserts the supplied issue is Ready via `get_item.sh --expect Ready`), snapshots it, moves it to In progress, and creates `feat/<issue>-<slug>` from `origin/main`.
2. `/issue-research <issue-number>` creates a tmux context session. Attach using the printed command and work in its `orchestrator` window. The orchestrator produces `docs/issue-workflows/<issue>/context.md` after user-approved research.
3. `/issue-plan <issue-number>` creates `plan.md` and self-contained task briefs under `docs/issue-workflows/<issue>/tasks/`.
4. For each brief, run `/issue-implement <issue-number> <task-file>`: implement, verify, stage, review the staged diff, and commit only on green.
5. `/issue-review <issue-number>` creates a tmux review-orchestrator session and dispatches five independent review workers. Resolve findings and repeat review as needed.
6. `/issue-open-pr <issue-number>` runs `check_review_gate.sh` (mechanical green gate), pushes the completed branch, opens a PR, and moves the board item to In review.
7. `/issue-archive <issue-number>` archives the workflow records into the knowledge-base vault and moves the board item to Done.

## Context research

Context gathering uses the agent state vocabulary:

```text
queued → running → reported → done
```

Workers run in interactive tmux windows. Switch to a window to inspect tool calls or steer work directly. Workers write only their own report and status under `docs/issue-workflows/<issue>/research/<todo>/`; the orchestrator is the sole writer of `context.md`.

## Review roles

The five final-review role contracts live in `scripts/issue-workflow/v2/roles/`
as plain files (`reviewer-<focus>.md`), not slash commands. Each takes the
issue number from its initial message and writes its report to
`docs/issue-workflows/<issue>/reviews/<focus>.md`, findings ordered by severity
with an explicit `No findings` section when applicable. Customize their
rubrics while preserving the report path.

- `reviewer-correctness` — correctness & safety: error handling, nil/aliasing/overflow, concurrency. `blocking`/`important`/`suggestion`.
- `reviewer-quality-depth` — tests, performance, observability, modernization to Go 1.26+ idioms. `important`/`suggestion`; observability & modernization are suggestion-first.
- `reviewer-quality` — style/idioms, naming, documentation; skips nitpicks. `blocking`/`important`/`suggestion`.
- `reviewer-security` — security (injection, auth, crypto, data exposure) and dependencies (CVEs, abandoned packages, `replace`). `blocking`/`important`/`suggestion`; supply-chain risk precedes style.
- `reviewer-requirements` — verifies each stated and clarified requirement against the implementation from `issue.md`, `context.md`, `plan.md`, and task briefs, flagging missing/partial/incorrect/out-of-scope behaviour.

## Glossary

| Term | Meaning |
|---|---|
| workflow | the issue lifecycle system (commands, scripts, roles, states) |
| run | one issue's passage through the workflow |
| phase | one stage of a run (research, plan, implement, review, pr) |
| role | a specialized subagent contract (a file under `scripts/issue-workflow/v2/roles/`) |
| dispatch | one execution of a role (interactive tmux window today; headless sandbox in v2) |
| track | S/M/L sizing of a run (v2) |
| gate | a human approval point (backlog, plan, PR) |
