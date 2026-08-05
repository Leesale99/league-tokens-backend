#!/usr/bin/env bash
set -euo pipefail

# Usage: start-session.sh <issue-number>
# Creates a detached tmux session containing the interactive context orchestrator.

issue_number="${1:?issue number is required}"
repo_root="$(git rev-parse --show-toplevel)"
issue_dir="$repo_root/docs/issue-workflows/$issue_number"
session="issue-$issue_number-context"

if [[ ! -f "$issue_dir/issue.md" ]]; then
  printf 'Missing issue snapshot: %s/issue.md\n' "$issue_dir" >&2
  exit 1
fi

mkdir -p "$issue_dir/research"
if [[ ! -f "$issue_dir/research/queue.md" ]]; then
  cat >"$issue_dir/research/queue.md" <<'EOF'
# Research queue

| ID | Research target | Role | State |
|---|---|---|---|
EOF
fi

if tmux has-session -t "$session" 2>/dev/null; then
  printf 'Context session already exists. Attach with:\n\ntmux attach -t %s\n' "$session"
  exit 0
fi

orchestrator_prompt="You are the context-gathering orchestrator for issue #$issue_number. Read scripts/issue-workflow/context/ORCHESTRATOR.md and follow it exactly."
printf -v orchestrator_command 'cd %q && exec pi --approve --name %q @%q %q' \
  "$repo_root" "Issue #$issue_number context orchestrator" "docs/issue-workflows/$issue_number/issue.md" "$orchestrator_prompt"
printf -v status_command 'cd %q && while true; do clear; scripts/issue-workflow/context/status.sh %q; sleep 2; done' \
  "$repo_root" "$issue_number"

tmux new-session -d -s "$session" -n orchestrator "$orchestrator_command"
tmux new-window -d -t "$session:" -n status "$status_command"

printf 'Context session created. Attach with:\n\ntmux attach -t %s\n' "$session"
