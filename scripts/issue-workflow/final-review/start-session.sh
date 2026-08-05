#!/usr/bin/env bash
set -euo pipefail

# Usage: start-session.sh <issue-number>
# Creates a detached tmux session containing the final-review orchestrator.

issue_number="${1:?issue number is required}"
repo_root="$(git rev-parse --show-toplevel)"
issue_dir="$repo_root/docs/issue-workflows/$issue_number"
session="issue-$issue_number-final-review"

if [[ ! -d "$issue_dir" ]]; then
  printf 'Missing issue workflow directory: %s\n' "$issue_dir" >&2
  exit 1
fi
mkdir -p "$issue_dir/reviews"

if tmux has-session -t "$session" 2>/dev/null; then
  printf 'Final-review session already exists. Attach with:\n\ntmux attach -t %s\n' "$session"
  exit 0
fi

prompt="You are the final-review orchestrator for issue #$issue_number. Read scripts/issue-workflow/final-review/ORCHESTRATOR.md and follow it exactly."
printf -v command 'cd %q && exec pi --approve --name %q %q' \
  "$repo_root" "Issue #$issue_number final review orchestrator" "$prompt"
tmux new-session -d -s "$session" -n orchestrator "$command"

printf 'Final-review session created. Attach with:\n\ntmux attach -t %s\n' "$session"
