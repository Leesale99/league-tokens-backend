# Issue workflow (v2)

The issue lifecycle runs headless: the `/issue-*` prompts (pi, repo-local in
`.pi/prompts/`) drive the conductor — the agent you are working with — through
mechanical gates, and every specialized agent runs in a disposable Docker
sandbox (sbx) with its own network policy and a read-only repo mount. There
is no tmux and no interactive worker window: sessions are headless dispatches
with JSONL event logs.

Per-issue records live OUTSIDE the repo at
`~/Projects/league-tokens/issue-workflows/<N>` (resolved by
`scripts/issue-workflow/v2/run_dir.sh <N>`): `issue.md`, `context.md`,
`plan.md`, `tasks/`, `research/`, `reviews/` (+ `archive/`), `workflow.json`,
`agents/*.jsonl`. The conductor's sandbox mounts the repo rw and the run dir
rw; role sandboxes get the repo `:ro` (task roles get the worktree instead)
plus the run dir. Nothing the workflow writes ever dirties `git status`.

## Lifecycle

1. `/issue-start [issue-number]` — selects a Ready board item (or asserts a
   numbered one via `get_item.sh --expect Ready`), snapshots it into the run
   dir (`capture_issue.sh`), moves the item to In progress, proposes the
   track (S/M/L) and records it (`mark.sh track` — creates `workflow.json`).
   No branch is created here.
2. `/issue-research <N>` — (tracks M/L) approves a research backlog, then
   dispatches the four researcher roles (repo/docs/web/kb) headlessly in
   parallel (`research.sh`); after human approval of the reports, the
   context synthesizer produces `context.md`.
3. `/issue-plan <N>` — (M/L) produces `plan.md` (TL;DR first; reviewability
   budgets ~300 LOC/task, ~800 LOC/PR) and self-contained task briefs under
   `tasks/`; Track L additionally runs the plan-critic pass (fresh-eyes
   adversarial review with dispositions recorded in `plan.md`). Track S
   writes ONE self-contained brief and skips research + plan ceremony.
4. `/issue-implement <N> <task-file>` — `v2/worktree.sh <N> <slug>` creates
   the feature branch `feat/<N>-<slug>` in `.worktrees/issue-<N>`; the
   implementer sandbox implements exactly the brief (typecheck + focused +
   full suite), stages only its files; the reviewer sandbox verifies the
   staged diff against the acceptance criteria and commits on green
   (`feat: <subject> (#N, task NN)`). Red → amend brief → re-dispatch
   (max 3 rounds).
5. `/issue-review <N>` — (M/L) `v2/review.sh` dispatches the five reviewer
   roles (correctness, quality, quality-depth, security, requirements) in
   parallel, each with its golang-* skills loaded (`--skill`, parity with
   CI). Blocking findings are fixed via new task briefs through
   `/issue-implement`, then re-reviewed incrementally (`--re-review` diffs
   `reviewed_head..HEAD`; only red focuses are re-dispatched; per-round
   telemetry proves the token savings). When every focus is green,
   `--finalize` writes `reviews/summary.md` — the mechanical gate.
6. `/issue-open-pr <N>` — runs `check_review_gate.sh` (Track S skips it —
   CI is the only gate), pushes the worktree branch and opens the PR
   (`open_pr.sh`), moves the board item to In review and updates labels.
7. `/issue-archive <N>` — archives the run dir into the knowledge-base
   vault (`archive_issue.sh`), writes the landing note (with the telemetry
   block from `v2/telemetry.sh`) + decision/lesson entries via the obsidian
   tool (single atomic vault commit; lesson-mining explicitly checks
   recurring review findings for prompt/skill updates), then
   `v2/cleanup.sh <N>` removes the issue's sandboxes and worktree, and the
   board item moves to Done.

## Tracks

- **S** — trivial: brief → implement → PR. No research, no plan ceremony,
  no local review; the CI pipeline is the only review gate. Escalate to M
  when the issue grows beyond one focused commit.
- **M** — default: research → plan → implement → review → PR.
- **L** — large: M + plan-critic pass + spike option + stacked-PR option.

Manifests: `scripts/issue-workflow/v2/tracks/{S,M,L}.md` (phases,
parallelism, agents, gates). `next.sh` is the mechanical state machine the
conductor follows between commands.

## Review roles

The five final-review contracts live in `scripts/issue-workflow/v2/roles/`
as plain files (`reviewer-<focus>.md`), not slash commands. Each reviews the
feature branch checkout inside the issue worktree (`git -C <worktree> diff
origin/main...HEAD`), never the main checkout, and writes
`reviews/<focus>.md` starting with a machine-read frontmatter block
(`reviewed_head`, `status: green|red`, `blocking_unresolved`,
`important_unresolved`).

- `reviewer-correctness` — error handling, safety (nil/aliasing/overflow),
  concurrency. `blocking`/`important`/`suggestion`.
- `reviewer-quality` — style/idioms, naming, documentation; skips
  nitpicks. `blocking`/`important`/`suggestion`.
- `reviewer-quality-depth` — tests, performance, observability,
  modernization to Go 1.21+ idioms. `important`/`suggestion`; observability
  and modernization are suggestion-first.
- `reviewer-security` — security (injection, auth, crypto, data exposure)
  and dependencies (CVEs, abandoned packages, `replace`). Supply-chain risk
  precedes style.
- `reviewer-requirements` — verifies every stated/clarified requirement
  from `issue.md`, `context.md`, `plan.md`, and the task briefs against the
  implementation.

The reviewers also audit the workflow's own scripts when something looks
wrong — the Phase 4 acceptance run surfaced eight genuine machinery bugs
(archive-before-overwrite, lock stale-steal, gate HEAD pinning, branch
ownership, …), each fixed and covered by the acceptance runners in
`v2/spike/`.

## Glossary

| Term | Meaning |
|---|---|
| workflow | the issue lifecycle system (prompts, scripts, roles, states) |
| run | one issue's passage through the workflow |
| run dir | per-issue record directory, outside the repo (`v2/run_dir.sh <N>`) |
| phase | one stage of a run (research, plan, implement, review, pr) |
| role | a specialized subagent contract (`v2/roles/*.md`) |
| dispatch | one headless execution of a role in its sandbox |
| sandbox | sbx Docker container per issue+role, reused across dispatches |
| worktree | `.worktrees/issue-<N>` holding the feature branch (`v2/worktree.sh`) |
| track | S/M/L sizing of a run (manifest: `v2/tracks/*.md`) |
| round | one review pass over the feature branch (`--re-review` = next round) |
| verdict | dispatch outcome: `reported` (report file present) or `failed` |
| gate | a mechanical check the conductor may not override (backlog, plan, PR) |
