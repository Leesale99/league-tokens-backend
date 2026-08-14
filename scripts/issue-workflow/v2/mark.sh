#!/usr/bin/env bash
# Usage: mark.sh <issue> <plan-done|task-run <task-file>|task-done <task-file> [commit]|pr-done|track <S|M|L> [reason]>
# Mechanical workflow.json bookkeeping for the conductor: records phase
# completions after their human gates. Keeps jq out of the prompts.
#
#   plan-done             plan approved → phase implement
#   task-run <task-file>  implementer dispatched for the task
#   task-done <task-file> [commit]  task committed green (reviewer's
#                        commit hash recorded when given)
#   pr-done               PR created → phase archive
#   track <S|M|L> [reason]  set/change the track at intake or mid-flight;
#                        creates workflow.json if absent; appends
#                        track_history {from, to, at, reason}

set -euo pipefail

issue="${1:?issue number is required}"
action="${2:?action is required (plan-done, task-done <task-file>, pr-done, track <S|M|L>)}"
run_dir="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_dir.sh" "$issue")"
wf="$run_dir/workflow.json"
[[ -d "$run_dir" ]] || { echo "mark: no run directory $run_dir — run /issue-start $issue first" >&2; exit 1; }
tmp="$wf.tmp.$$"
trap 'rm -f "$tmp"' EXIT

# track may be recorded before workflow.json exists (intake)
if [[ ! -f "$wf" ]]; then
  jq -n --argjson issue "$issue" \
    '{issue: $issue,
      track: null,
      track_history: [],
      phase: "research",
      phases: {
        research: {state: "pending", agents: {}},
        plan: {state: "pending"},
        implement: {state: "pending", tasks: {}},
        review: {state: "pending", reviewed_head: {}},
        pr: {state: "pending"}},
      telemetry: {research: {tokens: 0, wall_seconds: 0, dispatches: 0}}}' \
    >"$tmp" && mv "$tmp" "$wf"
fi

case "$action" in
  plan-done)
    jq '.phase = "implement" | .phases.plan.state = "done"' "$wf" >"$tmp"
    ;;
  task-run)
    task="${3:?task-run requires the task file name}"
    jq --arg task "$task" '.phases.implement.tasks[$task] = {state: "running"}' "$wf" >"$tmp"
    ;;
  task-done)
    task="${3:?task-done requires the task file name}"
    commit="${4:-}"
    jq --arg task "$task" --arg commit "$commit" \
      '.phases.implement.tasks[$task] = {state: "done", commit: $commit}' "$wf" >"$tmp"
    ;;
  pr-done)
    jq '.phase = "archive" | .phases.pr.state = "done"' "$wf" >"$tmp"
    ;;
  track)
    track="${3:-}"
    case "$track" in S|M|L) ;; *) echo "mark: track must be S, M, or L (got '${track:-}')" >&2; exit 2 ;; esac
    reason="${4:-confirmed at intake}"
    jq --arg to "$track" --arg reason "$reason" \
      '.track_history += [{from: .track, to: $to, at: (now | todateiso8601), reason: $reason}] |
       .track = $to' "$wf" >"$tmp"
    ;;
  *)
    echo "mark: unknown action '$action' (plan-done | task-done <task-file> | pr-done | track <S|M|L>)" >&2
    exit 2
    ;;
esac
mv "$tmp" "$wf"
printf 'mark: issue #%s · %s\n' "$issue" "$action"
