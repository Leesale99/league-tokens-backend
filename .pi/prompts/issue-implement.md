---
description: Implement and review one planned task, committing only on green
argument-hint: "<issue-number> <task-file>"
---
Implement and review task `$2` for issue #$1 (the `task-implementer` + `task-reviewer` roles, one command).

1. Read only `docs/issue-workflows/$1/tasks/$2` first. Read its referenced plan/context/issue files only if essential information is genuinely absent from the task brief; do not redo prior research.
2. Implement exactly the described work. Use `/skill:tdd` at suitable seams where practical.
3. Run typechecking and focused test files regularly. Run the full test suite once after the implementation is complete. Report commands and outcomes.
4. Inspect the final diff, then stage only the intended changes with `git add`.
5. Review `git diff --cached` against the task's acceptance criteria: bugs and logic errors, security issues, error-handling gaps. If you find any issue, report it precisely, return to step 2 to fix it, and re-stage.
6. When the staged review is green, create a focused commit on the current branch with a conventional message referencing the issue and task, e.g. `feat: add session validation (#46, task 01)`. State the commit hash and the verification performed.

Never stage unrelated changes. Do not alter unrelated existing changes.
