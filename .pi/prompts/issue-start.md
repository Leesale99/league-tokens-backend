---
description: Select a board issue, snapshot it, mark it in progress, and create its feature branch
argument-hint: "[issue-number]"
---
Start the issue workflow. The optional issue number is `$1`.

1. Run `scripts/issue-workflow/get_item.sh --expect Ready $1` when `$1` is supplied; otherwise run `scripts/issue-workflow/pick_ready.sh`. Both print the issue number, title, and board item ID as JSON. The numbered form asserts the item's board status is exactly Ready and exits non-zero otherwise; the unnumbered form only ever selects a Ready item. If either script fails or returns no item, report that and stop. Never fall back to Backlog.
2. Preserve the returned issue number, title, and board item ID.
3. Move the item to In progress with `scripts/issue-workflow/set_status.sh <item-id> in_progress`.
4. Snapshot the complete issue into `docs/issue-workflows/<issue>/issue.md` using `scripts/issue-workflow/capture_issue.sh <issue> <item-id>`. Do not overwrite an existing snapshot; ask the user how to proceed if one exists.
5. Create the branch from `origin/main` with `scripts/issue-workflow/create_branch.sh <issue> <title>`. It must refuse a dirty checkout or an existing branch rather than modifying anything unexpectedly.
6. Search the knowledge base (skill `knowledge-base`, vault `league-tokens`) for prior art on the issue's key topics: related archive entries, decisions, and lessons.
7. Report the issue number/title, snapshot path, branch name, any prior-art hits from the knowledge base, and that the issue is ready for context gathering with `/issue-research <issue>`.

Do not create a worktree and do not begin research or implementation in this phase.
