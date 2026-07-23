---
name: implement-from-board
description: >
  Pick up a task from the GitHub project board, implement it, and open a PR.
  Use this skill whenever the user says "implement from board", "pick up the next task",
  "work on the next ticket", "start the next issue", "grab a task from the board",
  or any variation of wanting to pull work from the project board and build it.
  Also trigger when the user says "implement ticket #N" or "work on issue #N" with
  a specific number. This skill handles the git workflow (worktree, branch, PR, board
  updates) and delegates implementation to a sub-agent running the /implement skill.
---

# Implement From Board

Pick up a task from the GitHub project board, create a git worktree, delegate
implementation to a sub-agent, then open a PR and update the board.

All scripts live in `scripts/` relative to this skill. Config (project IDs,
field IDs, option IDs) lives in `config.json`.

## Workflow

### Step 1: Select a task

If the user provided an issue number, pass it as an argument. Otherwise call
the script with no arguments to get the first "Ready" item:

```bash
scripts/query_ready.sh [issue_number]
```

Output: `{"number": N, "title": "...", "item_id": "PVTI_..."}`

If no items are in "Ready", tell the user and stop — do not fall back to "Backlog".

### Step 2: Fetch issue details

```bash
gh issue view <number> --json title,body,labels,comments
```

Save the title, body, and acceptance criteria — the sub-agent needs them.

### Step 3: Move to "In progress"

```bash
scripts/move_status.sh <item_id> in_progress
```

### Step 4: Create worktree and branch

Derive a slug from the title: lowercase, spaces → hyphens, strip special chars,
truncate to 40 chars. Example: "Scaffold + lint + CI" → `scaffold-lint-ci`.

```bash
scripts/create_worktree.sh <number> <slug>
```

Output: `{"worktree_path": "...", "branch_name": "feat/N-slug"}`

### Step 5: Implement (sub-agent)

Spawn a sub-agent using the Task tool. The sub-agent receives the /implement
skill instructions and works independently in the worktree directory.

Prompt for the sub-agent:

> You are implementing issue #<number>: <title>
>
> Working directory: <worktree_path>
>
> Issue body:
> <body>
>
> Acceptance criteria:
> <criteria>
>
> Follow the /implement skill: use TDD, run typechecking and tests regularly,
> run the full test suite at the end. Commit your work when done.

Wait for the sub-agent to complete before proceeding.

### Step 6: Open a PR

```bash
scripts/open_pr.sh <worktree_path> <number> "feat(<area>): <title>" "<summary>"
```

Output: `{"pr_url": "..."}`

### Step 7: Update the board

```bash
scripts/move_status.sh <item_id> in_review
scripts/remove_label.sh <number> ready-for-agent
scripts/add_label.sh <number> ready-for-human
```

Only one workflow label should be on the issue at a time: `ready-for-agent`
while it's in the queue, `ready-for-human` when the PR is up for review.

### Step 8: Clean up and report

```bash
scripts/cleanup_worktree.sh <number>
```

Tell the user:
- The PR URL
- Issue number and title
- Board updated to "In review" with label `ready-for-human`
- Remind them to review and merge

## Error handling

- If a worktree already exists, ask the user whether to remove or reuse it.
- If the sub-agent fails or the user cancels, move the board back to "Ready"
  and clean up the worktree.
