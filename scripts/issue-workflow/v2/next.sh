#!/usr/bin/env bash
# Usage: next.sh <issue>
# Conductor's state resolver: prints the run's current state and the exact
# next command — or precisely what blocks it. Mechanical, no LLM judgement.
# Reads workflow.json when present and probes artifacts otherwise.
#
#   exit 0 → stdout starts with `next:` — /issue-next executes that phase
#   exit 1 → stdout starts with `blocked:` — present the reason, do not
#            improvise around it
#
# The phase order is the standard pipeline (research → plan → implement →
# review → pr → archive); track manifests (Task 2.2) will select phases.

set -euo pipefail

issue="${1:?issue number is required}"
repo_root="$(git rev-parse --show-toplevel)"
run_dir="$repo_root/docs/issue-workflows/$issue"
wf="$run_dir/workflow.json"

[[ -d "$run_dir" ]] || {
  echo "blocked: no run directory $run_dir — start with /issue-start $issue"
  exit 1
}
[[ -f "$run_dir/issue.md" ]] || {
  echo "blocked: no issue snapshot at docs/issue-workflows/$issue/issue.md — run /issue-start $issue"
  exit 1
}
[[ -f "$wf" ]] || {
  echo "next: /issue-research $issue (workflow.json absent — research will initialize it)"
  exit 0
}

# ---- track manifest (Task 2.2): selects the phases to run. Missing
# ---- manifest = misconfiguration; report precisely.
track="$(jq -r '.track // "M"' "$wf")"
manifest="$repo_root/scripts/issue-workflow/v2/tracks/$track.md"
[[ -f "$manifest" ]] || {
  echo "blocked: track manifest missing: scripts/issue-workflow/v2/tracks/$track.md (workflow.json track field is malformed)"
  exit 1
}
phases="$(awk -F': ' '$1 == "phases" {print $2; exit}' "$manifest")"
has_phase() { [[ ",${phases}," == *",$1,"* ]]; }

# ---- research phase (skipped for tracks without it, e.g. S)
if has_phase research; then
rstate="$(jq -r '.phases.research.state // "pending"' "$wf")"
case "$rstate" in
  running)
    echo "next: /issue-research $issue (dispatch in progress — resume)"
    exit 0
    ;;
  gated)
    failed="$(jq -r '[.phases.research.agents | to_entries[] | select(.value.state == "failed") | .key] | join(", ")' "$wf")"
    if [[ -n "$failed" ]]; then
      echo "blocked: research agents failed: $failed — amend their briefs, then run: scripts/issue-workflow/v2/research.sh $issue --redispatch"
      exit 1
    fi
    if [[ ! -f "$run_dir/context.md" ]]; then
      echo "next: /issue-research $issue (reports ready — synthesize context.md)"
    else
      echo "next: /issue-research $issue (context.md ready — approve it, then research.sh $issue --finalize)"
    fi
    exit 0
    ;;
  pending)
    echo "next: /issue-research $issue (propose and approve the research backlog)"
    exit 0
    ;;
  done) : ;;  # fall through to plan
  *)
    echo "blocked: unexpected research phase state: $rstate (workflow.json is malformed)"
    exit 1
    ;;
esac
fi  # has_phase research

# ---- plan phase (skipped for tracks without it)
if has_phase plan; then
pstate="$(jq -r '.phases.plan.state // "pending"' "$wf")"
if [[ "$pstate" != "done" ]]; then
  if [[ -f "$run_dir/plan.md" && -d "$run_dir/tasks" ]]; then
    # v1 flow wrote plan.md + task briefs only after human approval
    echo "next: /issue-implement $issue <task> (plan artifacts exist — mark it done with: scripts/issue-workflow/v2/mark.sh $issue plan-done, then re-run /issue-next)"
    exit 0
  fi
  echo "next: /issue-plan $issue (approve the plan and task briefs)"
  exit 0
fi
fi  # has_phase plan

# ---- implement phase ----
pending_task="$(jq -r '[.phases.implement.tasks // {} | to_entries[] | select((if (.value | type) == "object" then .value.state else .value end) != "done") | .key] | sort | .[0] // empty' "$wf")"
if [[ -n "$pending_task" ]]; then
  echo "next: /issue-implement $issue $pending_task"
  exit 0
fi
tracked_count="$(jq -r '.phases.implement.tasks // {} | length' "$wf")"
if [[ "$tracked_count" -eq 0 ]]; then
  first_task=""
  for f in "$run_dir"/tasks/*.md; do
    [[ -f "$f" ]] || continue
    first_task="$(basename "$f")"
    break
  done
  if [[ -n "$first_task" ]]; then
    echo "next: /issue-implement $issue $first_task"
    exit 0
  fi
  echo "blocked: no tasks under docs/issue-workflows/$issue/tasks/ — run /issue-plan $issue first"
  exit 1
fi
# tracked tasks exist: pick the first pending one, else the first brief that
# was never tracked (hybrid flow), else final review.
if [[ -z "$pending_task" ]]; then
  for f in "$run_dir"/tasks/*.md; do
    [[ -f "$f" ]] || continue
    b="$(basename "$f")"
    in_map="$(jq -r --arg b "$b" '.phases.implement.tasks[$b] | if type == "object" then .state else . end // empty' "$wf")"
    if [[ -z "$in_map" ]]; then pending_task="$b"; break; fi
  done
fi
if [[ -n "$pending_task" ]]; then
  echo "next: /issue-implement $issue $pending_task"
  exit 0
fi
# all tracked tasks done → final review

# ---- review / pr / archive phases ----
prstate="$(jq -r '.phases.pr.state // "pending"' "$wf")"
if [[ "$prstate" == "done" ]]; then
  echo "next: /issue-archive $issue (PR merged? — archive closes the run)"
  exit 0
fi
if has_phase review; then
  if bash "$repo_root/scripts/issue-workflow/check_review_gate.sh" "$issue" >/dev/null 2>&1; then
    echo "next: /issue-open-pr $issue (review gate green)"
  else
    echo "next: /issue-review $issue (final review — gate not green yet)"
  fi
else
  # Track S: no local review — CI is the only review gate
  echo "next: /issue-open-pr $issue (track $track — no local review; CI is the gate)"
fi
exit 0
