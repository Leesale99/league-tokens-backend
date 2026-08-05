#!/usr/bin/env bash
set -euo pipefail

# Usage: status.sh <issue-number>
# Renders the worker-owned status files. Safe to call from the orchestrator or watch pane.

issue_number="${1:?issue number is required}"
root="docs/issue-workflows/$issue_number/research"

printf 'Issue #%s context research\n\n' "$issue_number"
printf '%-22s %-16s %s\n' 'TODO' 'STATE' 'REPORT'
printf '%-22s %-16s %s\n' '----' '-----' '------'

found=false
for status in "$root"/*/status.json; do
  [[ -f "$status" ]] || continue
  found=true
  todo_id="$(basename "$(dirname "$status")")"
  state="$(jq -r '.state // "invalid"' "$status" 2>/dev/null || printf 'invalid')"
  report='-'
  [[ -f "$(dirname "$status")/report.md" ]] && report='ready'
  printf '%-22s %-16s %s\n' "$todo_id" "$state" "$report"
done

if [[ "$found" == false ]]; then
  printf '%-22s %-16s %s\n' '(none)' '-' '-'
fi

printf '\nPrimary states: queued → working → review → done\n'
