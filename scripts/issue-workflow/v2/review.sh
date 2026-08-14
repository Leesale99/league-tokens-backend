#!/usr/bin/env bash
# Usage: review.sh <issue> [--redispatch]
# Dispatches the five final-review focuses in parallel (manifest
# parallelism.review), collects reports under reviews/<focus>.md, and
# updates workflow.json (phase state + telemetry). Host-side.
#
# Task 4.1 — parity with CI: the same five focuses as pr-pipeline.yml
# (correctness, quality, quality-depth, security, requirements), the same
# golang-* skills loaded per focus via --skill (baked into the image),
# and the same read-only posture: reviewers only write their report.
#
# Track S refuses: its gates are brief,pr — the CI pipeline is the only
# review gate (parallelism.review: 0 in tracks/S.md). Reviewers diff the
# feature branch inside the issue worktree, so the worktree must exist
# and every implemented task must be done.
#
# Modes:
#   (none)       dispatch the five focuses (resumes a running phase)
#   --redispatch flip failed agents back to queued and re-run the pool
#                (after the human amended whatever they reviewed)

set -euo pipefail

issue="${1:?issue number is required}"
mode="${2:-}"
case "$mode" in ""|--redispatch) ;; *) echo "review: unknown mode: $mode" >&2; exit 1 ;; esac
repo_root="$(git rev-parse --show-toplevel)"
v2="$repo_root/scripts/issue-workflow/v2"
run_dir="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_dir.sh" "$issue")"
wf="$run_dir/workflow.json"

die() { printf 'review: %s\n' "$*" >&2; exit 1; }

[[ -f "$wf" ]] || die "workflow.json missing — run /issue-start $issue first"

# ---- 0. track gates (Track S: no local final review) ----
track="$(jq -r '.track // "M"' "$wf")"
manifest="$v2/tracks/$track.md"
[[ -f "$manifest" ]] || die "track manifest missing: $manifest"
parallel="$(awk -F': ' '$1 == "parallelism.review" {print $2; exit}' "$manifest" 2>/dev/null || true)"
[[ "$parallel" =~ ^[0-9]+$ ]] || parallel=5
if [[ "$parallel" == "0" ]]; then
  die "track $track has parallelism.review: 0 — no local final review; CI is the gate"
fi

# ---- 1. preconditions: worktree + implemented tasks ----
[[ -f "$repo_root/.worktrees/issue-$issue/.git" ]] \
  || die "worktree missing at $repo_root/.worktrees/issue-$issue — run v2/worktree.sh <issue> <slug> first"
tasks="$(jq -r '.phases.implement.tasks // {} | to_entries | map(select(.value.state != "done")) | length' "$wf")"
[[ "$tasks" =~ ^[0-9]+$ ]] || die "cannot read .phases.implement.tasks from $wf"
(( tasks == 0 )) || die "$tasks implemented task(s) not done — finish /issue-implement first"

# ---- 2. phase state machine (mirrors research.sh) ----
phase="$(jq -r '.phases.review.state // "pending"' "$wf")"
if [[ "$phase" == "done" ]]; then
  printf 'review: issue #%s is already done — next: /issue-open-pr %s\n' "$issue" "$issue"
  exit 0
fi
if [[ "$mode" == "--redispatch" ]]; then
  [[ "$phase" == "gated" ]] || die "--redispatch requires a gated review phase (got: $phase)"
  jq '.phases.review.state = "running" | .phases.review.agents |= map_values(if .state == "failed" then .state = "queued" else . end)' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
else
  case "$phase" in
    gated)
      printf 'review: issue #%s is already gated — human review of the findings pending.\n' "$issue"
      printf 'next:      /issue-review %s (read the reports; plan fixes for blocking findings)\n' "$issue"
      exit 0
      ;;
    pending) jq '.phases.review.state = "running"' "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf" ;;
    running) : ;;  # resume: dispatch whatever is still queued
    *) die "unexpected review phase state: $phase" ;;
  esac
fi

# ---- 3. register the five focus agents (roles from the track manifest) ----
roles="$(awk -F': ' '$1 == "agents.review" {print $2; exit}' "$manifest" 2>/dev/null || true)"
roles="${roles//,/ }"   # manifest lists are comma-separated
[[ -n "$roles" ]] || die "agents.review missing from $manifest"
brief_dir="$run_dir/review-briefs"
mkdir -p "$brief_dir"
for role in $roles; do
  focus="${role#reviewer-}"
  case "$role" in
    reviewer-correctness|reviewer-quality|reviewer-quality-depth|reviewer-security|reviewer-requirements) ;;
    *) die "manifest agents.review has an unknown role: $role" ;;
  esac
  brief="$brief_dir/$focus.md"
  printf '# Review focus: %s\n\nRun the %s role contract (named in your dispatch message). Review the feature branch checkout (read-only) in the issue worktree, write the report at the path in your dispatch message, then stop.\n' \
    "$focus" "$role" > "$brief"
  jq --arg topic "$focus" --arg role "$role" --arg issue "$issue" --arg brief "$brief" \
    '.phases.review.agents[$topic] //= {role: $role, state: "queued", sandbox: ("issue-" + $issue + "-" + $role), brief: $brief, report: ("reviews/" + $topic + ".md")}' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
done

# ---- 4. pre-create each role's sandbox once (sequential — avoids a
# ---- create race between parallel dispatches of the same role)
for role in $roles; do
  focus="${role#reviewer-}"
  bash "$v2/dispatch.sh" --create-only "$issue" "$role" "$brief_dir/$focus.md" >/dev/null
done

# ---- 5. dispatch the queued focuses in parallel (manifest budget) ----
pids=()
for role in $roles; do
  focus="${role#reviewer-}"
  state="$(jq -r --arg t "$focus" '.phases.review.agents[$t].state // "queued"' "$wf")"
  [[ "$state" == "queued" ]] || continue
  while (( $(jobs -rp | wc -l | tr -d ' ') >= parallel )); do sleep 1; done
  bash "$v2/dispatch.sh" "$issue" "$role" "$brief_dir/$focus.md" &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p" || true; done

# ---- 6. finalize: phase → gated, telemetry totals (single writer) ----
jq '.phases.review.state = "gated" |
    .telemetry.review = {
      tokens: ([.phases.review.agents[].telemetry | .tokens // 0] | add),
      wall_seconds: ([.phases.review.agents[].telemetry | .wall_seconds // 0] | add),
      dispatches: (.phases.review.agents | length)}' \
  "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"

# ---- 7. summary ----
printf 'review    issue #%s — phase gated (awaiting human review)\n\n' "$issue"
printf '%-24s %-22s %-9s %s\n' 'FOCUS' 'ROLE' 'STATE' 'REPORT'
jq -r '.phases.review.agents | to_entries[] |
       [.key, .value.role, .value.state, .value.report] | @tsv' "$wf" \
  | awk -F '\t' '{printf "%-24s %-22s %-9s %s\n", $1, $2, $3, $4}'
printf '\ntelemetry: %s tokens · %s s · %s dispatches\n' \
  "$(jq -r '.telemetry.review.tokens' "$wf")" \
  "$(jq -r '.telemetry.review.wall_seconds' "$wf")" \
  "$(jq -r '.telemetry.review.dispatches' "$wf")"
printf 'next:      /issue-review %s (read the reports; plan fixes for blocking findings)\n' "$issue"
