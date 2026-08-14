#!/usr/bin/env bash
# Usage: research.sh <issue> [--finalize|--redispatch]
# Dispatches the approved research backlog in parallel (≤4), collects
# reports, and updates workflow.json (phase state + telemetry). Host-side.
#
# The backlog is the set of briefs: issue-workflows/<N>/research/ (run_dir.sh)
# <NN>-<slug>/brief.md. Each brief's FIRST LINE must be `role: <role>`
# (a research role from the v2 README table) so the dispatch is
# mechanical. Workflow phases: pending → running → gated → done.
# Agent states: queued → running → reported | failed.
#
# Modes:
#   (none)       dispatch the queued backlog (resumes a running phase)
#   --finalize   mark research done after the human approved context.md
#   --redispatch flip failed agents back to queued (after the human
#                amends their briefs) and re-run the dispatch pool

set -euo pipefail

issue="${1:?issue number is required}"
mode="${2:-}"
case "$mode" in ""|--finalize|--redispatch) ;; *) die "unknown mode: $mode" ;; esac
repo_root="$(git rev-parse --show-toplevel)"
v2="$repo_root/scripts/issue-workflow/v2"
run_dir="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_dir.sh" "$issue")"
research_dir="$run_dir/research"
wf="$run_dir/workflow.json"

die() { printf 'research: %s\n' "$*" >&2; exit 1; }

[[ -d "$research_dir" ]] || die "no research dir: $research_dir — approve a backlog and write the briefs first"

briefs=()
for b in "$research_dir"/*/brief.md; do
  [[ -f "$b" ]] && briefs+=("$b")
done
(( ${#briefs[@]} > 0 )) || die "no briefs under $research_dir — approve a backlog first"

# ---- 1. workflow.json: init if absent (§4.1 schema; track proposal lands in Task 2.2)
if [[ ! -f "$wf" ]]; then
  jq -n --argjson issue "$issue" \
    '{issue: $issue,
      track: "M",
      track_history: [{from: null, to: "M", at: (now | todateiso8601), reason: "intake (fallback init — /issue-start records the confirmed track via mark.sh track)"}],
      phase: "research",
      phases: {
        research: {state: "pending", agents: {}},
        plan: {state: "pending"},
        implement: {state: "pending", tasks: {}},
        review: {state: "pending", reviewed_head: {}},
        pr: {state: "pending"}},
      telemetry: {research: {tokens: 0, wall_seconds: 0, dispatches: 0}}}' \
    >"$wf.tmp.$$"
  mv "$wf.tmp.$$" "$wf"
fi

phase="$(jq -r '.phases.research.state // "pending"' "$wf")"

if [[ "$phase" == "done" ]]; then
  printf 'research: issue #%s is already done — next: /issue-plan %s\n' "$issue" "$issue"
  exit 0
fi

if [[ "$mode" == "--finalize" ]]; then
  [[ "$phase" == "gated" ]] || die "--finalize requires a gated research phase (got: $phase)"
  [[ -f "$run_dir/context.md" ]] || die "--finalize requires context.md — dispatch the context-synthesizer first"
  jq '.phase = "plan" | .phases.research.state = "done" | .phases.research.agents |= map_values(if .state == "reported" then .state = "done" else . end) |
      .telemetry.research = {
        tokens: ([.phases.research.agents[].telemetry | .tokens // 0] | add),
        wall_seconds: ([.phases.research.agents[].telemetry | .wall_seconds // 0] | add),
        dispatches: (.phases.research.agents | length)}' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  printf 'research: issue #%s — phase done\n' "$issue"
  printf 'next:      /issue-plan %s\n' "$issue"
  exit 0
fi

if [[ "$mode" == "--redispatch" ]]; then
  [[ "$phase" == "gated" ]] || die "--redispatch requires a gated research phase (got: $phase)"
  jq '.phases.research.state = "running" | .phases.research.agents |= map_values(if .state == "failed" then .state = "queued" else . end)' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  # fall through to the dispatch pool below
else
  case "$phase" in
    gated)
      printf 'research: issue #%s is already gated — no re-dispatch.\n' "$issue"
      printf 'next:      /issue-research %s (synthesize context.md; human reviews it)\n' "$issue"
      exit 0
      ;;
    pending) jq '.phases.research.state = "running"' "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf" ;;
    running) : ;;  # resume: dispatch whatever is still queued
    *) die "unexpected research phase state: $phase" ;;
  esac
fi

# ---- 2. register queued agent entries (idempotent)
for brief in "${briefs[@]}"; do
  topic="$(basename "$(dirname "$brief")")"
  role="$(head -1 "$brief" | sed -E 's/^role:[[:space:]]*//')"
  case "$role" in
    repo-researcher|docs-researcher|web-researcher|kb-researcher) ;;
    *) die "brief $brief has no valid role on line 1 (got: '${role:-}') — expected 'role: <research-role>'" ;;
  esac
  jq --arg topic "$topic" --arg role "$role" --arg brief "$brief" --arg issue "$issue" \
    '.phases.research.agents[$topic] //= {role: $role, state: "queued", sandbox: ("issue-" + $issue + "-" + $role), brief: $brief, report: ("research/" + $topic + "/report.md")}' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
done

# ---- 3. pre-create each role's sandbox once (sequential — avoids a
# ---- create race between parallel dispatches of the same role)
for role in $(jq -r '.phases.research.agents[].role' "$wf" | sort -u); do
  first_brief="$(jq -r --arg r "$role" '.phases.research.agents | to_entries[] | select(.value.role == $r) | .value.brief' "$wf" | head -1)"
  bash "$v2/dispatch.sh" --create-only "$issue" "$role" "$first_brief" >/dev/null
done

# ---- 4. dispatch the queued backlog in parallel (budget from the track manifest)
track="$(jq -r '.track // "M"' "$wf")"
manifest="$v2/tracks/$track.md"
parallel="$(awk -F': ' '$1 == "parallelism.research" {print $2; exit}' "$manifest" 2>/dev/null || true)"
[[ "$parallel" =~ ^[0-9]+$ ]] || parallel=4
pids=()
for brief in "${briefs[@]}"; do
  topic="$(basename "$(dirname "$brief")")"
  state="$(jq -r --arg t "$topic" '.phases.research.agents[$t].state // "queued"' "$wf")"
  [[ "$state" == "queued" ]] || continue
  role="$(head -1 "$brief" | sed -E 's/^role:[[:space:]]*//')"
  while (( $(jobs -rp | wc -l | tr -d ' ') >= parallel )); do sleep 1; done
  bash "$v2/dispatch.sh" "$issue" "$role" "$brief" &
  pids+=("$!")
done
for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || true; done

# ---- 5. finalize: phase → gated, phase telemetry totals (single writer)
jq '.phases.research.state = "gated" |
    .telemetry.research = {
      tokens: ([.phases.research.agents[].telemetry | .tokens // 0] | add),
      wall_seconds: ([.phases.research.agents[].telemetry | .wall_seconds // 0] | add),
      dispatches: (.phases.research.agents | length)}' \
  "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"

# ---- 6. summary
printf 'research  issue #%s — phase gated (awaiting human review)\n\n' "$issue"
printf '%-24s %-20s %-9s %s\n' 'TOPIC' 'ROLE' 'STATE' 'REPORT'
jq -r '.phases.research.agents | to_entries[] |
       [.key, .value.role, .value.state, .value.report] | @tsv' "$wf" \
  | awk -F '\t' '{printf "%-24s %-20s %-9s %s\n", $1, $2, $3, $4}'
printf '\ntelemetry: %s tokens · %s s · %s dispatches\n' \
  "$(jq -r '.telemetry.research.tokens' "$wf")" \
  "$(jq -r '.telemetry.research.wall_seconds' "$wf")" \
  "$(jq -r '.telemetry.research.dispatches' "$wf")"
printf 'next:      /issue-research %s — synthesize context.md, then the human approves it\n' "$issue"
