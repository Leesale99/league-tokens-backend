---
description: Start the independent five-reviewer final review session for an issue
argument-hint: "<issue-number>"
---
Start the final full review session for issue #$1.

0. Resolve the run dir: `RUN_DIR=$(scripts/issue-workflow/v2/run_dir.sh $1)` — it lives outside the repo.
1. Confirm `$RUN_DIR/` exists and that the current branch contains the intended committed work.
2. Run `scripts/issue-workflow/final-review/start-session.sh $1`.
3. Report the printed `tmux attach` command. Explain that the orchestrator will read every issue document, dispatch the five independent reviewer role contracts from `scripts/issue-workflow/v2/roles/`, collect their reports under `$RUN_DIR/reviews/`, and wait for findings to be fixed and re-reviewed.

Do not open a PR in this launcher session.
