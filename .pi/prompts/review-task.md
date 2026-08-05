---
description: Review staged changes for one task and commit only when they are sound
argument-hint: "<issue-number> <task-file>"
---
Review the staged changes for task `$2` of issue #$1.

1. Read `docs/issue-workflows/$1/tasks/$2` and inspect `git diff --cached`. If nothing is staged, stop and report that no commit was made.
2. Review specifically for bugs and logic errors, security issues, and error-handling gaps. Check the staged diff against the task acceptance criteria.
3. If you find any issue, report it precisely and do not commit. Return to `/implement-task $1 $2` to fix it.
4. If the review is green, create a focused commit on the current branch. State the commit hash and the verification performed.

Never stage unrelated changes while reviewing.
