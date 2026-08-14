---
description: Select a board issue, snapshot it, mark it in progress, and create its feature branch
argument-hint: "[issue-number]"
---
Start the issue workflow. The optional issue number is `$1`.

1. Run `scripts/issue-workflow/get_item.sh --expect Ready $1` when `$1` is supplied; otherwise run `scripts/issue-workflow/pick_ready.sh`. Both print the issue number, title, and board item ID as JSON. The numbered form asserts the item's board status is exactly Ready and exits non-zero otherwise; the unnumbered form only ever selects a Ready item. If either script fails or returns no item, report that and stop. Never fall back to Backlog.
2. Preserve the returned issue number, title, and board item ID.
3. Move the item to In progress with `scripts/issue-workflow/set_status.sh <item-id> in_progress`.
4. Resolve the run dir first: `scripts/issue-workflow/v2/run_dir.sh <issue>` — all workflow records live there, OUTSIDE the repo (the conductor's sandbox mounts it rw). Then snapshot the complete issue into `<run-dir>/issue.md` using `scripts/issue-workflow/capture_issue.sh <issue> <item-id>`. Do not overwrite an existing snapshot; ask the user how to proceed if one exists.
5. Do NOT create any branch here — the feature branch `feat/<issue>-<slug>` is created by `scripts/issue-workflow/v2/worktree.sh <issue> <slug>` at implement time (the legacy `create_branch.sh` switches the main checkout onto the feature branch, which would break the worktree and pollute main).
6. **Propose a track** (S/M/L) from signals: size label, acceptance-criteria count, contexts touched, ambiguity. Present the choice with a one-line justification; the human confirms or changes it. Then record it: `scripts/issue-workflow/v2/mark.sh <issue> track <S|M|L> "<reason>"` — this creates `workflow.json` with the track and the `track_history` entry.
7. Quick prior-art check in the knowledge base (skill `knowledge-base`, vault `league-tokens`): related archive entries, decisions, lessons. Minutes, not a phase — thorough mining is kb-researcher's job in research; for Track S this is the only check.
8. Report the issue number/title, snapshot path, branch name, confirmed track, any prior-art hits from the knowledge base, and that the issue is ready for context gathering with `/issue-research <issue>` (Track S: ready for the brief with `/issue-plan <issue>`).

Do not create a worktree and do not begin research or implementation in this phase.
