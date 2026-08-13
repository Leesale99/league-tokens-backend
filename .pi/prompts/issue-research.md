---
description: Start an interactive, tmux-backed research and context-gathering session
argument-hint: "<issue-number>"
---
Start the dedicated context-gathering session for issue #$1.

1. Confirm `docs/issue-workflows/$1/issue.md` exists.
2. Run `scripts/issue-workflow/context/start-session.sh $1`.
3. Report the printed `tmux attach` command and tell the user that the `orchestrator` window is the main interactive session, the `status` window shows the live todo state, and worker windows allow direct inspection and steering.

Do not research in this launcher session. The interactive orchestrator is initialized with the complete workflow instructions in `scripts/issue-workflow/context/ORCHESTRATOR.md`.
