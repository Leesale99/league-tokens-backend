---
description: Implement and stage one planned task without committing it
argument-hint: "<issue-number> <task-file>"
---
Implement task `$2` for issue #$1.

1. Read only `docs/issue-workflows/$1/tasks/$2` first. Read its referenced plan/context/issue files only if essential information is genuinely absent from the task brief; do not redo prior research.
2. Implement exactly the described work. Use `/skill:tdd` at suitable seams where practical.
3. Run typechecking and focused test files regularly. Run the full test suite once after the implementation is complete. Report commands and outcomes.
4. Inspect the final diff, then stage only the intended changes with `git add`.
5. Do **not** commit. The next phase, `/review-task`, reviews `git diff --cached` and commits only if it is acceptable.

Do not alter unrelated existing changes.
