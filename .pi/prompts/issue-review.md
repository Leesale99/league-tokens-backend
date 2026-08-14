---
description: Run the five-reviewer final review headlessly (parallel sbx dispatches)
argument-hint: "<issue-number>"
---
Start the final review for issue #$1.

0. Resolve the run dir: `RUN_DIR=$(scripts/issue-workflow/v2/run_dir.sh $1)` — it lives outside the repo.
1. Confirm `$RUN_DIR/` exists, the issue worktree exists (`scripts/issue-workflow/v2/worktree.sh $1` re-prints its path — never recreate it), and the worktree branch contains the intended committed work.
2. **Track S** (read `jq -r '.track' $RUN_DIR/workflow.json`): refuse — Track S has no local final review; the CI pipeline is the only review gate. Report `next: /issue-open-pr $1`.
3. Run `scripts/issue-workflow/v2/review.sh $1` — it dispatches the five reviewer roles (correctness, quality, quality-depth, security, requirements) in parallel to their own sandboxes, each with the matching `golang-*` skills loaded (`--skill`, parity with CI), and waits. Reports land at `$RUN_DIR/reviews/<focus>.md`; every report carries a machine-read `reviewed_head:` line.
4. Read all five reports and present a **findings summary** to the user: per focus, every `blocking` finding first (file/line, evidence, impact), then `important` ones; note each report's `reviewed_head`.
5. If any report has blocking findings — the review is red. Do NOT open a PR. Work with the user to plan the fixes (amend existing task briefs or write new ones under `$RUN_DIR/tasks/`); the fix loop goes through `/issue-implement`, then a re-review. If every report is green (or only suggestions), the review is green — report `next: /issue-open-pr $1`.

Do not open a PR in this session.
