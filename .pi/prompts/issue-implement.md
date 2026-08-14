---
description: Implement and review one planned task headlessly in the worktree sandbox
argument-hint: "<issue-number> <task-file>"
---
Implement and review task `$2` for issue #$1 headlessly (the `task-implementer` + `task-reviewer` roles in the worktree sandbox, one command).

0. Resolve the run dir: `RUN_DIR=$(scripts/issue-workflow/v2/run_dir.sh $1)` — it lives outside the repo; use it for every path below.
1. Read `$RUN_DIR/tasks/$2` (it is also attached to each dispatch below).
2. Ensure the worktree exists: derive the branch slug from the issue title (lowercase, dashes, ≤40 chars) and run `scripts/issue-workflow/v2/worktree.sh $1 <slug>` — it prints the worktree path and reuses it on re-run.
3. Run `scripts/issue-workflow/v2/mark.sh $1 task-run $2` (task → running).
4. Dispatch the implementer: `scripts/issue-workflow/v2/dispatch.sh $1 task-implementer $RUN_DIR/tasks/$2`. If the verdict is `failed`, present the reason, amend the brief with the user, and re-dispatch.
5. Dispatch the reviewer: `scripts/issue-workflow/v2/dispatch.sh $1 task-reviewer $RUN_DIR/tasks/$2`. Read the review report at `<worktree>/docs/issue-workflows/$1/reports/<task-name>.review.md` (task filename without its `.md` suffix, e.g. `01-add-validation.review.md` — the worktree path is what `worktree.sh` printed in step 2; the reports dir is git-ignored inside the worktree).
6. **`verdict: red` → fix loop**: present the findings, amend `$RUN_DIR/tasks/$2` with the user (incorporate the required fixes into the brief), re-dispatch the implementer (step 4) then the reviewer (step 5), and re-read the verdict. Never exceed 3 fix rounds without escalating to the user.
7. **`verdict: green`**: run `scripts/issue-workflow/v2/mark.sh $1 task-done $2 <commit-sha>` (sha from the review report's `commit:` line). Report the commit subject + sha, the verification performed, and `next: /issue-next $1`.

Never push, never open a PR from here. The worktree branch accumulates one commit per task; `worktree.sh $1 remove` cleans up at archive.
