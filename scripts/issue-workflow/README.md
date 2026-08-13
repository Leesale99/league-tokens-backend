# Issue workflow support

The prompt templates in `.pi/prompts/` use these scripts for GitHub-board actions, branch creation, and tmux-backed context/review sessions.

- `get_item.sh`, `pick_ready.sh`, `move_status.sh`, `add_label.sh`, `remove_label.sh`: GitHub Project and issue-label operations. `get_item.sh <N>` is a status-agnostic board lookup (prints number/title/item_id/status; `--expect <status>` asserts it); `pick_ready.sh` picks the first Ready item.
- `capture_issue.sh`: immutable issue snapshot at `docs/issue-workflows/<issue>/issue.md`.
- `create_branch.sh`: creates `feat/<issue>-<slug>` from `origin/main`; it refuses a dirty checkout.
- `open_pr.sh`: requires a clean, committed branch named `feat/<issue>-*`; it pushes, creates a pull request, and kills the issue's leftover tmux sessions. `archive_issue.sh` also kills leftover sessions.
- `check_review_gate.sh`: machine-checkable final-review gate; exits 0 only when `reviews/summary.md` frontmatter is `status: green`, `blocking_unresolved: 0`, and `reviewed_head` matches the current HEAD.
- `context/`: session creation, worker dispatch, and status display for context gathering.
- `final-review/`: session creation and reviewer dispatch for final review.

## tmux

The workflow creates detached tmux sessions. Attach with the command printed by the launcher, then switch directly to a worker window to inspect or steer it.

For reliable modified Enter keys in Pi, use the recommended tmux configuration from Pi's `docs/tmux.md`:

```tmux
set -g extended-keys on
set -g extended-keys-format csi-u
```
