#!/usr/bin/env bash
# Usage: review.sh <issue> [--re-review|--finalize]
# Dispatches the five final-review focuses in parallel (manifest
# parallelism.review), collects reports under reviews/<focus>.md, and
# updates workflow.json (phase state + round telemetry). Host-side.
#
# Task 4.1 — parity with CI: the same five focuses as pr-pipeline.yml
# (correctness, quality, quality-depth, security, requirements), the same
# golang-* skills loaded per focus via --skill (baked into the image),
# and the same read-only posture: reviewers only write their report.
#
# Task 4.2 — incremental re-review: every report records its reviewed_head
# (frontmatter); each round snapshots per-focus telemetry into
# .telemetry.review.rounds[]. --re-review re-dispatches ONLY the focuses
# whose last report is red (blocking findings) against the incremental
# diff <reviewed_head>..HEAD (fix verification; whole-diff context stays
# available). --finalize aggregates the reports into reviews/summary.md
# (Task 0.2 gate frontmatter: status, blocking_unresolved, reviewed_head)
# and marks the phase done.
#
# Track S refuses: its gates are brief,pr — the CI pipeline is the only
# review gate (parallelism.review: 0 in tracks/S.md). Reviewers diff the
# feature branch inside the issue worktree, so the worktree must exist
# and every implemented task must be done.

set -euo pipefail

issue="${1:?issue number is required}"
mode="${2:-}"
case "$mode" in ""|--re-review|--finalize) ;; *) echo "review: unknown mode: $mode" >&2; exit 1 ;; esac
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
roles="$(awk -F': ' '$1 == "agents.review" {print $2; exit}' "$manifest" 2>/dev/null || true)"
roles="${roles//,/ }"   # manifest lists are comma-separated
[[ -n "$roles" ]] || die "agents.review missing from $manifest"

# ---- 1. preconditions: worktree + implemented tasks ----
[[ -f "$repo_root/.worktrees/issue-$issue/.git" ]] \
  || die "worktree missing at $repo_root/.worktrees/issue-$issue — run v2/worktree.sh <issue> <slug> first"
tasks="$(jq -r '.phases.implement.tasks // {} | to_entries | map(select(.value.state != "done")) | length' "$wf")"
[[ "$tasks" =~ ^[0-9]+$ ]] || die "cannot read .phases.implement.tasks from $wf"
(( tasks == 0 )) || die "$tasks implemented task(s) not done — finish /issue-implement first"

phase="$(jq -r '.phases.review.state // "pending"' "$wf")"
round="$(jq -r '.phases.review.round // 1' "$wf")"
[[ "$round" =~ ^[0-9]+$ ]] || die "bad .phases.review.round: $round"

# ---- frontmatter helpers (the role contract's machine-read block) ----
fm() { sed -n 's/^'"$1"':[[:space:]]*//p' "$2" | head -1; }

focus_for() { # role -> focus name
  local r="$1"; printf '%s' "${r#reviewer-}"
}

# ---- 2. mode dispatch ----
if [[ "$mode" == "--finalize" ]]; then
  [[ "$phase" == "gated" ]] || die "--finalize requires a gated review phase (got: $phase)"
  head_sha="$(git -C "$repo_root/.worktrees/issue-$issue" rev-parse HEAD)"
  rows=(); blocking_total=0; red=()
  for role in $roles; do
    focus="$(focus_for "$role")"
    report="$run_dir/reviews/$focus.md"
    [[ -f "$report" ]] || die "no report for $focus — re-run review.sh first"
    status="$(fm status "$report")"; [[ "$status" =~ ^(green|red)$ ]] || die "$focus: bad frontmatter status '$status'"
    blocking="$(fm blocking_unresolved "$report")"; [[ "$blocking" =~ ^[0-9]+$ ]] || die "$focus: bad blocking_unresolved '$blocking'"
    important="$(fm important_unresolved "$report")"; [[ "$important" =~ ^[0-9]+$ ]] || important=0
    head_fm="$(fm reviewed_head "$report")"
    rows+=("| $focus | $status | $blocking | $important | ${head_fm:-?} |")
    blocking_total=$((blocking_total + blocking))
    [[ "$status" == "red" ]] && red+=("$focus")
  done
  if (( blocking_total > 0 )); then
    die "summary is red ($blocking_total unresolved blocking finding(s) in: ${red[*]}) — plan fixes, then review.sh <issue> --re-review"
  fi
  {
    printf -- '---\nstatus: green\nblocking_unresolved: 0\nreviewed_head: %s\n---\n' "$head_sha"
    printf '# Review summary — issue #%s (round %s)\n\n' "$issue" "$round"
    printf '| Focus | Status | Blocking | Important | Reviewed head |\n'
    printf '|---|---|---|---|---|\n'
    for r in "${rows[@]}"; do printf '%s\n' "$r"; done
    printf '\nGate (Task 0.2): check_review_gate.sh %s — status green, blocking_unresolved 0, reviewed_head %s.\n' "$issue" "$head_sha"
  } > "$run_dir/reviews/summary.md"
  jq '.phases.review.state = "done"' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  printf 'review: issue #%s — phase done; summary.md written (green).\n' "$issue"
  printf 'next:      /issue-open-pr %s\n' "$issue"
  exit 0
fi

if [[ "$mode" == "--re-review" ]]; then
  [[ "$phase" == "gated" ]] || die "--re-review requires a gated review phase (got: $phase)"
  prev="$((round - 1))"
  red=()
  for role in $roles; do
    focus="$(focus_for "$role")"
    agent_state="$(jq -r --arg f "$focus" '.phases.review.agents[$f].state // "missing"' "$wf")"
    [[ "$agent_state" == "reported" ]] || die "focus $focus was not reported in round $prev (state: $agent_state) — run review.sh <issue> first"
    report="$run_dir/reviews/$focus.md"
    status="$(fm status "$report")"
    if [[ "$status" == "red" ]]; then red+=("$focus"); fi
  done
  if (( ${#red[@]} == 0 )); then
    die "no focus is red — nothing to re-review; run review.sh <issue> --finalize"
  fi
  round=$((round + 1))   # this round is the next one
  printf 'review: issue #%s — re-review round %s for: %s\n' "$issue" "$round" "${red[*]}"
  jq --argjson round "$round" '.phases.review.state = "running" | .phases.review.round = $round' \
    "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  # fall through to the re-review pool (briefs below are fix-verification)
else
  case "$phase" in
    done)
      printf 'review: issue #%s is already done — next: /issue-open-pr %s\n' "$issue" "$issue"
      exit 0 ;;
    gated)
      printf 'review: issue #%s is already gated (round %s).\n' "$issue" "$round"
      printf 'next:      /issue-review %s (read the reports; fixes → --re-review, green → --finalize)\n' "$issue"
      exit 0 ;;
    pending)
      jq --argjson round "$round" '.phases.review.state = "running" | .phases.review.round = $round' \
        "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf" ;;
    running) : ;;  # resume: dispatch whatever is still queued
    *) die "unexpected review phase state: $phase" ;;
  esac
fi

# ---- 3. register queued focus agents (round 1: all five; re-review:
# ---- only the red focuses, against their previous reviewed_head)
brief_dir="$run_dir/review-briefs"
mkdir -p "$brief_dir"
[[ "$mode" == "--re-review" ]] && queued=("${red[@]}") || queued=()
this_round=()
for role in $roles; do
  focus="$(focus_for "$role")"
  case "$role" in
    reviewer-correctness|reviewer-quality|reviewer-quality-depth|reviewer-security|reviewer-requirements) ;;
    *) die "manifest agents.review has an unknown role: $role" ;;
  esac
  if [[ "$mode" == "--re-review" ]] && ! [[ " ${queued[*]} " == *" $focus "* ]]; then
    continue   # green focuses keep their round-1 verdict
  fi
  this_round+=("$focus")
  brief="$brief_dir/$focus.md"
  if [[ "$mode" == "--re-review" ]]; then
    prev_head="$(jq -r --arg f "$focus" '.phases.review.reviewed_head[$f] // ""' "$wf")"
    if [[ ! "$prev_head" =~ ^[0-9a-f]{7,40}$ ]]; then
      # fallback: the report's own frontmatter is the authority
      prev_head="$(fm reviewed_head "$run_dir/reviews/$focus.md")"
    fi
    [[ "$prev_head" =~ ^[0-9a-f]{7,40}$ ]] || die "$focus: no previous reviewed_head recorded for re-review"
    printf '# Fix-verification round (issue #%s)\n\nRun the %s role contract (named in your dispatch message). Previous round reviewed %s; read your previous report (archived at reviews/archive/%s.r%d.md — dispatch.sh archives the pre-round report before overwriting) and verify EVERY blocking/important finding in it against the INCREMENTAL diff:\n\n    git -C <worktree> diff %s...HEAD\n\nMark each finding resolved or still-open; flag regressions. The full diff (git -C <worktree> diff origin/main...HEAD) remains available for context. Write the report at the path in your dispatch message, then stop.\n' \
      "$issue" "$role" "$prev_head" "$focus" "$((round - 1))" "$prev_head" > "$brief"
  else
    printf '# Review focus: %s\n\nRun the %s role contract (named in your dispatch message). Review the feature branch checkout (read-only) in the issue worktree, write the report at the path in your dispatch message, then stop.\n' \
      "$focus" "$role" > "$brief"
  fi
  if [[ "$mode" == "--re-review" ]]; then
    # FORCE re-queue: //= would keep the round-N state (reported) and the
    # pool would skip the focus — round 2 would silently re-snapshot round
    # 1 (host acceptance, Phase 4: identical per-focus token counts).
    jq --arg topic "$focus" --arg role "$role" --arg issue "$issue" --arg brief "$brief" \
      '.phases.review.agents[$topic] = {role: $role, state: "queued", sandbox: ("issue-" + $issue + "-" + $role), brief: $brief, report: ("reviews/" + $topic + ".md")}' \
      "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  else
    jq --arg topic "$focus" --arg role "$role" --arg issue "$issue" --arg brief "$brief" \
      '.phases.review.agents[$topic] //= {role: $role, state: "queued", sandbox: ("issue-" + $issue + "-" + $role), brief: $brief, report: ("reviews/" + $topic + ".md")}' \
      "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"
  fi
done

# ---- 4. pre-create each role's sandbox once (sequential — avoids a
# ---- create race between parallel dispatches of the same role)
for role in $roles; do
  focus="$(focus_for "$role")"
  [[ -f "$brief_dir/$focus.md" ]] || continue   # not in this round
  bash "$v2/dispatch.sh" --create-only "$issue" "$role" "$brief_dir/$focus.md" >/dev/null
done

# ---- 5. dispatch the queued focuses in parallel (manifest budget) ----
pids=()
for role in $roles; do
  focus="$(focus_for "$role")"
  state="$(jq -r --arg t "$focus" '.phases.review.agents[$t].state // "queued"' "$wf")"
  [[ "$state" == "queued" ]] || continue
  while (( $(jobs -rp | wc -l | tr -d ' ') >= parallel )); do sleep 1; done
  bash "$v2/dispatch.sh" "$issue" "$role" "$brief_dir/$focus.md" &
  pids+=("$!")
done
for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || true; done

# ---- 6. finalize round: phase → gated, reviewed_head + telemetry
# ---- snapshot (single writer)
heads="{}"; statuses="{}"
for role in $roles; do
  focus="$(focus_for "$role")"
  report="$run_dir/reviews/$focus.md"
  [[ -f "$report" ]] || continue
  h="$(fm reviewed_head "$report")"
  [[ "$h" =~ ^[0-9a-f]{7,40}$ ]] || die "$focus: report lacks a valid reviewed_head frontmatter line"
  heads="$(jq --arg f "$focus" --arg h "$h" '.[$f] = $h' <<<"$heads")"
  st="$(fm status "$report")"
  [[ "$st" =~ ^(green|red)$ ]] || die "$focus: report lacks a valid status frontmatter line (got: '${st:-}')"
  statuses="$(jq --arg f "$focus" --arg s "$st" '.[$f] = $s' <<<"$statuses")"
done
if (( ${#this_round[@]} > 0 )); then
  dispatched_json="$(printf '%s\n' "${this_round[@]}" | jq -R . | jq -s -c .)"
else
  dispatched_json='[]'
fi
jq --argjson round "$round" --argjson heads "$heads" --argjson statuses "$statuses" \
   --argjson dispatched "$dispatched_json" \
  '.phases.review.state = "gated" |
   .phases.review.reviewed_head = $heads |
   .telemetry.review.rounds[($round - 1)] = {
     round: $round, at: (now | todateiso8601), dispatched: $dispatched,
     agents: (.phases.review.agents | to_entries | map(.value = {state: .value.state, status: $statuses[.key], tokens: (.value.telemetry.tokens // 0), wall_seconds: (.value.telemetry.wall_seconds // 0)}) | from_entries)} |
   .telemetry.review.tokens = ([.telemetry.review.rounds[].agents[]?.tokens // 0] | add) |
   .telemetry.review.wall_seconds = ([.telemetry.review.rounds[].agents[]?.wall_seconds // 0] | add) |
   .telemetry.review.dispatches = (.phases.review.agents | length)' \
  "$wf" >"$wf.tmp.$$" && mv "$wf.tmp.$$" "$wf"

# ---- 7. summary ----
printf 'review    issue #%s — phase gated (round %s, awaiting human review)\n\n' "$issue" "$round"
printf '%-24s %-22s %-9s %-10s %s\n' 'FOCUS' 'ROLE' 'STATE' 'REVIEWED' 'REPORT'
jq -r '.phases.review.agents | to_entries[] |
       [.key, .value.role, .value.state, (.value.state // ""), .value.report] | @tsv' "$wf" \
  | awk -F '\t' '{printf "%-24s %-22s %-9s %-10s %s\n", $1, $2, $3, $4, $5}'
printf '\nround %s: %s tokens · %s s\n' \
  "$round" \
  "$(jq -r --argjson r "$((round - 1))" '.telemetry.review.rounds[$r].agents | [.[]?.tokens] | add // 0' "$wf" 2>/dev/null || echo 0)" \
  "$(jq -r --argjson r "$((round - 1))" '.telemetry.review.rounds[$r].agents | [.[]?.wall_seconds] | add // 0' "$wf" 2>/dev/null || echo 0)"
printf 'next:      /issue-review %s (read the reports; fixes → --re-review, green → --finalize)\n' "$issue"
