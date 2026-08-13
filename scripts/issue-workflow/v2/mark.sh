#!/usr/bin/env bash
# Usage: mark.sh <issue> <plan-done|task-done <task-file>|pr-done>
# Mechanical workflow.json bookkeeping for the conductor: records phase
# completions after their human gates. Keeps jq out of the prompts.
#
#   plan-done             plan approved → phase implement
#   task-done <task-file> a task committed green (e.g. 01-add-session-validation.md)
#   pr-done               PR created → phase archive

set -euo pipefail

issue="${1:?issue number is required}"
action="${2:?action is required (plan-done, task-done <task-file>, pr-done)}"
repo_root="$(git rev-parse --show-toplevel)"
wf="$repo_root/docs/issue-workflows/$issue/workflow.json"
[[ -f "$wf" ]] || { echo "mark: workflow.json missing — run research.sh $issue first" >&2; exit 1; }
tmp="$wf.tmp.$$"
trap 'rm -f "$tmp"' EXIT

case "$action" in
  plan-done)
    jq '.phase = "implement" | .phases.plan.state = "done"' "$wf" >"$tmp"
    ;;
  task-done)
    task="${3:?task-done requires the task file name}"
    jq --arg task "$task" '.phases.implement.tasks[$task] = "done"' "$wf" >"$tmp"
    ;;
  pr-done)
    jq '.phase = "archive" | .phases.pr.state = "done"' "$wf" >"$tmp"
    ;;
  *)
    echo "mark: unknown action '$action' (plan-done | task-done <task-file> | pr-done)" >&2
    exit 2
    ;;
esac
mv "$tmp" "$wf"
printf 'mark: issue #%s · %s\n' "$issue" "$action"
