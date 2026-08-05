---
description: Start the independent five-reviewer final review session for an issue
argument-hint: "<issue-number>"
---
Start the final full review session for issue #$1.

1. Confirm `docs/issue-workflows/$1/` exists and that the current branch contains the intended committed work.
2. Run `scripts/issue-workflow/final-review/start-session.sh $1`.
3. Report the printed `tmux attach` command. Explain that the orchestrator will read every issue document, dispatch the five independent placeholder review commands, collect their reports under `docs/issue-workflows/$1/reviews/`, and wait for findings to be fixed and re-reviewed.

Do not open a PR in this launcher session.
