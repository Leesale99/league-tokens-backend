#!/usr/bin/env bash
set -euo pipefail

# Usage: close-worker.sh <issue-number> <todo-id>
# Close a finished worker window after its report has been accepted or rejected.

issue_number="${1:?issue number is required}"
todo_id="${2:?todo id is required}"
session="issue-$issue_number-context"

tmux kill-window -t "$session:$todo_id"
