# Issue workflow

This repository uses project-local Pi prompt templates for the issue lifecycle. They replace the retired `implement-from-board` skill.

## Workflow

1. `/start-issue [issue-number]` selects a Ready board item (or validates the supplied issue), snapshots it, moves it to In progress, and creates `feat/<issue>-<slug>` from `origin/main`.
2. `/gather-context <issue-number>` creates a tmux context session. Attach using the printed command and work in its `orchestrator` window. The orchestrator produces `docs/issue-workflows/<issue>/context.md` after user-approved research.
3. `/plan-issue <issue-number>` creates `plan.md` and self-contained task briefs under `docs/issue-workflows/<issue>/tasks/`.
4. For each brief, run `/implement-task <issue-number> <task-file>`, then `/review-task <issue-number> <task-file>`.
5. `/final-review <issue-number>` creates a tmux review-orchestrator session and dispatches five independent review workers. Resolve findings and repeat review as needed.
6. `/open-pr <issue-number>` pushes the completed branch, opens a PR, and moves the board item to In review.
7. After GitHub confirms the issue is `CLOSED`, run `/archive-closed-issue <issue-number>` before discarding the local branch or worktree. It creates a vault archive branch and PR, verifies the merged archive on vault `main`, and only then proposes a separate backend cleanup PR. Opening either PR is not an archive or deletion trigger.

## Knowledge-base publication boundary

The active issue workflow remains canonical in this backend repository until the issue is closed and its archive is verified. The separate `Leesale99/vault-league-tokens` repository is the reviewed publication channel for Obsidian knowledge. Agents must:

- use `obsidian` with `vault="league-tokens"` for every vault content operation;
- never push directly to vault `main`;
- treat an unmerged vault branch or PR as draft context;
- merge the vault archive PR and verify its Manifest on vault `main` before removing `docs/issue-workflows/<issue>/`;
- remove exactly that directory only through a separate, reviewed backend cleanup PR;
- preserve unrelated pre-existing backend changes and never run Graphify as part of issue workflow archival.

For source mirror changes, use `/sync-project-wiki --mode check|plan|apply|verify` and follow `30 Engineering/Source Sync Protocol.md` in the vault.

## Context research

Context gathering uses four primary states:

```text
queued → working → review → done
```

Workers run in interactive tmux windows. Switch to a window to inspect tool calls or steer work directly. Workers write only their own report and status under `docs/issue-workflows/<issue>/research/<todo>/`; the orchestrator is the sole writer of `context.md`.

## Review templates

The five review workers live in `.pi/prompts/`. Each takes an `<issue-number>` argument and writes its report to `docs/issue-workflows/<issue>/reviews/<name>.md`, findings ordered by severity with an explicit `No findings` section when applicable. Customize their rubrics while preserving the issue argument and report path.

- `review-correctness` — correctness & safety: error handling, nil/aliasing/overflow, concurrency. `blocking`/`important`/`suggestion`.
- `review-quality-depth` — tests, performance, observability, modernization to Go 1.21+ idioms. `important`/`suggestion`; observability & modernization are suggestion-first.
- `review-quality` — style/idioms, naming, documentation; skips nitpicks. `blocking`/`important`/`suggestion`.
- `review-security` — security (injection, auth, crypto, data exposure) and dependencies (CVEs, abandoned packages, `replace`). `blocking`/`important`/`suggestion`; supply-chain risk precedes style.
- `review-requirements` — verifies each stated and clarified requirement against the implementation from `issue.md`, `context.md`, `plan.md`, and task briefs, flagging missing/partial/incorrect/out-of-scope behaviour.
