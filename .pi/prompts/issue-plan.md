---
description: Turn approved issue context into an implementation plan and self-contained task briefs
argument-hint: "<issue-number>"
---
Plan issue #$1.

1. Read `docs/issue-workflows/$1/issue.md` and `docs/issue-workflows/$1/context.md`. If context is absent or contains blockers, stop and explain what must be resolved.
2. **Track S only** (read the track with `jq -r '.track' docs/issue-workflows/$1/workflow.json`): skip the multi-task ceremony below. Propose ONE self-contained task brief written from `issue.md` alone (no `plan.md`, no research input). On human approval write it to `docs/issue-workflows/$1/tasks/01-<slug>.md`, run `scripts/issue-workflow/v2/mark.sh $1 plan-done`, and report `next: /issue-implement $1 <task-file>`. Do not continue to step 3.
3. Propose a detailed plan split into small, independently testable tasks. State task ordering, dependencies, affected paths/seams, verification, risks, and how the plan satisfies acceptance criteria.
3. Ask the user for feedback. Iterate until they explicitly approve the plan; do not write durable task files before approval.
4. Write the approved plan to `docs/issue-workflows/$1/plan.md`.
5. Create one self-contained task brief per task under `docs/issue-workflows/$1/tasks/`, named in ordered form such as `01-add-session-validation.md`.

Every task brief must contain:

- `# Task NN: <title>` and a **Description** explaining the issue, plan, and this task's role in the larger outcome.
- **Context** containing only the specific verified information needed to do this task.
- **Acceptance criteria** as precise, testable, verifiable checkboxes.
- **Implementation and verification guidance** sufficient to work independently.
- **References** to `plan.md`, `context.md`, and `issue.md`, explicitly marked: read these only when essential information is missing from this task brief. Research is complete; do not restart it by default.

The task brief is the worker's primary and normally only context.
