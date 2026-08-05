# Issue workflow support

The prompt templates in `.pi/prompts/` use these scripts for GitHub-board actions, branch creation, and tmux-backed context/review sessions.

- `query_ready.sh`, `move_status.sh`, `add_label.sh`, `remove_label.sh`: GitHub Project and issue-label operations.
- `capture_issue.sh`: immutable issue snapshot at `docs/issue-workflows/<issue>/issue.md`.
- `create_branch.sh`: creates `feat/<issue>-<slug>` from `origin/main`; it refuses a dirty checkout.
- `open_pr.sh`: requires a clean, committed feature branch; it pushes and creates a pull request.
- `context/`: session creation, worker dispatch, and status display for context gathering.
- `final-review/`: session creation and reviewer dispatch for final review.

## tmux

The workflow creates detached tmux sessions. Attach with the command printed by the launcher, then switch directly to a worker window to inspect or steer it.

For reliable modified Enter keys in Pi, use the recommended tmux configuration from Pi's `docs/tmux.md`:

```tmux
set -g extended-keys on
set -g extended-keys-format csi-u
```
