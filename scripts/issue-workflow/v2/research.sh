#!/usr/bin/env bash
# Usage: research.sh <issue>
# Dispatches the approved research backlog in parallel (≤4), collects
# reports, and updates workflow.json (phase state + telemetry). Host-side.
#
# The backlog is the set of briefs: docs/issue-workflows/<N>/research/
# <NN>-<slug>/brief.md. Each brief's FIRST LINE must be `role: <role>`
# (a research role from the v2 README table) so the dispatch is
# mechanical. Workflow phases: pending → running → gated (awaiting
# human approval of the reports/context). Agent states:
# queued → running → reported | failed.

set -euo pipefail

issue="${1:?issue number is required}"
repo_root="$(git rev-parse --show-toplevel)"
v2="$repo_root/scripts/issue-workflow/v2"
run_dir="$repo_root/docs/issue-workflows/$issue"
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
      track_history: [{from: null, to: "M", at: (now | todateiso8601), reason: "intake (provisional; track proposal lands in Task 2.2)"}],
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
case "$phase" in
  gated|done)
    printf 'research: issue #%s is already %s — no re-dispatch.\n' "$issue" "$phase"
    printf 'next:      /issue-research %s (human reviews the reports)\n' "$issue"
    exit 0
    ;;
  pending) jq '.phases.research.state = "running"' "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf" ;;
  running) : ;;  # resume: dispatch whatever is still queued
  *) die "unexpected research phase state: $phase" ;;
esac

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

# ---- 4. dispatch the queued backlog in parallel, at most 4 at once
pids=()
for brief in "${briefs[@]}"; do
  topic="$(basename "$(dirname "$brief")")"
  state="$(jq -r --arg t "$topic" '.phases.research.agents[$t].state // "queued"' "$wf")"
  [[ "$state" == "queued" ]] || continue
  role="$(head -1 "$brief" | sed -E 's/^role:[[:space:]]*//')"
  while (( $(jobs -rp | wc -l | tr -d ' ') >= 4 )); do sleep 1; done
  bash "$v2/dispatch.sh" "$issue" "$role" "$brief" &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p" || true; done

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
printf 'next:      /issue-research %s — human approves the reports (synthesis lands in Task 1.3)\n' "$issue"
