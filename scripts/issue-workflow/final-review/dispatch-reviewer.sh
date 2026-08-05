#!/usr/bin/env bash
set -euo pipefail

# Usage: dispatch-reviewer.sh <issue-number> <correctness|quality-depth|quality|security|requirements>

issue_number="${1:?issue number is required}"
review="${2:?review name is required}"
repo_root="$(git rev-parse --show-toplevel)"
session="issue-$issue_number-final-review"

case "$review" in correctness|quality-depth|quality|security|requirements) ;; *)
  echo 'Unknown review. Use correctness, quality-depth, quality, security, or requirements.' >&2
  exit 1
esac
if ! tmux has-session -t "$session" 2>/dev/null; then
  printf 'Final-review tmux session does not exist: %s\n' "$session" >&2
  exit 1
fi

case "$review" in
  quality-depth) command_name='review-quality-depth' ;;
  *) command_name="review-$review" ;;
esac
prompt="/$command_name $issue_number"
printf -v command 'cd %q && exec pi --approve --name %q %q' \
  "$repo_root" "Issue #$issue_number review $review" "$prompt"
tmux new-window -d -t "$session:" -n "$review" "$command"
printf 'Reviewer started. Open it with:\n\ntmux select-window -t %s:%s\n' "$session" "$review"
