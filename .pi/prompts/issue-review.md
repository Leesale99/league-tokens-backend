---
description: Run and close the five-reviewer final review (parallel sbx, incremental re-review loop)
argument-hint: "<issue-number>"
---
Run the final review for issue #$1.

0. Resolve the run dir: `RUN_DIR=$(scripts/issue-workflow/v2/run_dir.sh $1)` — it lives outside the repo.
1. Confirm `$RUN_DIR/` exists, the issue worktree exists (`scripts/issue-workflow/v2/worktree.sh $1` re-prints its path — never recreate it), and the worktree branch contains the intended committed work.
2. **Track S** (read `jq -r '.track' $RUN_DIR/workflow.json`): refuse — Track S has no local final review; the CI pipeline is the only review gate. Report `next: /issue-open-pr $1`.
3. If the review phase is not gated yet, run `scripts/issue-workflow/v2/review.sh $1` — it dispatches the five reviewer roles (correctness, quality, quality-depth, security, requirements) in parallel to their own sandboxes, each with the matching `golang-*` skills loaded (`--skill`, parity with CI), and waits. Reports land at `$RUN_DIR/reviews/<focus>.md`, each starting with the machine-read frontmatter block (`reviewed_head`, `status`, `blocking_unresolved`, `important_unresolved`).
4. Read all reports from the latest round and present a **findings summary** to the user: per focus, every `blocking` finding first (file/line, evidence, impact), then `important` ones; note the round number and each report's `reviewed_head`.

**If any report is red (blocking findings):**
5. Do NOT open a PR. Work with the user to plan the fixes: amend existing task briefs or write new ones under `$RUN_DIR/tasks/`; each fix goes through `/issue-implement $1 <task-file>` (the reviewer commits it on the feature branch).
6. Re-review only what changed: run `scripts/issue-workflow/v2/review.sh $1 --re-review` — it re-dispatches ONLY the red focuses against the incremental diff `reviewed_head..HEAD` (fix verification; the whole-diff context stays available). Repeat the findings presentation; loop steps 5–6 until no focus is red. Round telemetry is snapshotted per round (`telemetry.review.rounds`) — the incremental round must consume measurably fewer tokens.

**When every report is green:**
7. Run `scripts/issue-workflow/v2/review.sh $1 --finalize` — it aggregates the reports into `$RUN_DIR/reviews/summary.md` (frontmatter: `status: green`, `blocking_unresolved: 0`, `reviewed_head: <sha>`) and marks the review phase done.
8. Confirm the mechanical gate: `scripts/issue-workflow/check_review_gate.sh $1` exits 0. Report `next: /issue-open-pr $1`.

Do not open a PR in this session.
