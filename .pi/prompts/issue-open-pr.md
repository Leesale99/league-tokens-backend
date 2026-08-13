---
description: Push the finished branch, open its pull request, and update the board
argument-hint: "<issue-number>"
---
Finish issue #$1 by opening its pull request.

1. Run `scripts/issue-workflow/check_review_gate.sh $1`. If it exits non-zero, report its message and stop — the gate is mechanical; do not override it with your own judgement of the findings. Otherwise read `docs/issue-workflows/$1/issue.md` and `plan.md` for the PR title and summary.
2. Confirm no tracked changes remain, the current branch is a feature branch, and all intended work is committed. Local untracked records under `docs/issue-workflows/$1/` are permitted; any other untracked files are not.
3. Derive the PR title from the issue title and write a concise summary of implementation and verification. Run `scripts/issue-workflow/open_pr.sh $1 <title> <summary>`.
4. Only after PR creation succeeds, obtain the board item with `scripts/issue-workflow/get_item.sh $1` (status-agnostic lookup), move it to In review with `scripts/issue-workflow/set_status.sh`, remove `ready-for-agent`, and add `ready-for-human` using the workflow scripts.
5. Report the PR URL, issue number/title, branch, board status, label changes, and a reminder to review and merge.

Do not create or clean up a worktree.
