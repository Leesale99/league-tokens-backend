#!/usr/bin/env bash
# Usage: telemetry.sh <issue-number>
# Prints the run's telemetry as a markdown block for the archive landing
# note's `## Telemetry` section (Task 5.2). Reads <run>/workflow.json.
set -euo pipefail

issue="${1:?issue number is required}"
run_dir="$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_dir.sh" "$issue")"
wf="$run_dir/workflow.json"
[[ -f "$wf" ]] || { printf 'telemetry: workflow.json missing: %s\n' "$wf" >&2; exit 1; }

human() { # tokens -> 4.32M / 88k / 123
  awk -v n="$1" 'BEGIN { if (n >= 1000000) printf "%.2fM", n/1000000; else if (n >= 1000) printf "%.1fk", n/1000; else printf "%d", n }'
}
secs() { # seconds -> integer
  awk -v n="$1" 'BEGIN { printf "%d", n }'
}

r_tok="$(jq -r '.telemetry.research.tokens // 0' "$wf")"
r_wall="$(jq -r '.telemetry.research.wall_seconds // 0' "$wf")"
r_disp="$(jq -r '.telemetry.research.dispatches // 0' "$wf")"

# implement: task-implementer/task-reviewer agents (phase "implement" since
# Task 5.2; older runs have them under research.agents — sum both)
impl_tok="$(jq -r '[.phases.implement.agents[]?.telemetry.tokens // 0] | add // 0' "$wf")"
impl_wall="$(jq -r '[.phases.implement.agents[]?.telemetry.wall_seconds // 0] | add // 0' "$wf")"
impl_disp="$(jq -r '[.phases.implement.agents[]?] | length' "$wf")"
legacy_impl_tok="$(jq -r '[(.phases.research.agents // {}) | to_entries[]? | select(.value.role == "task-implementer" or .value.role == "task-reviewer") | (.value.telemetry.tokens // 0)] | add // 0' "$wf")"
impl_tok=$((impl_tok + legacy_impl_tok))
impl_wall=$((impl_wall + 0))

rev_tok="$(jq -r '.telemetry.review.tokens // 0' "$wf")"
rev_wall="$(jq -r '.telemetry.review.wall_seconds // 0' "$wf")"
rev_disp="$(jq -r '.telemetry.review.dispatches // 0' "$wf")"
rounds="$(jq -r '.telemetry.review.rounds // [] | length' "$wf")"
track="$(jq -r '.track // "?"' "$wf")"
per_round="$(jq -r '[.telemetry.review.rounds[].agents | [.[].tokens // 0] | add] | map(if . >= 1000000 then (. / 1000000 * 100 | round / 100 | tostring + "M") elif . >= 1000 then (. / 1000 * 10 | round / 10 | tostring + "k") else tostring end) | join(" → ")' "$wf" 2>/dev/null || echo "")"

total=$((r_tok + impl_tok + rev_tok))

printf '## Telemetry\n\n'
printf 'Track: %s%s\n\n' "$track" "$([ "$rounds" -gt 0 ] && printf ' · review rounds: %s' "$rounds")"
printf '| Phase | Tokens | Wall (s) | Dispatches |\n'
printf '|---|---|---|---|\n'
printf '| research | %s | %s | %s |\n' "$(human "$r_tok")" "$(secs "$r_wall")" "$r_disp"
printf '| implement | %s | %s | %s |\n' "$(human "$impl_tok")" "$(secs "$impl_wall")" "$impl_disp"
printf '| review | %s | %s | %s |\n' "$(human "$rev_tok")" "$(secs "$rev_wall")" "$rev_disp"
printf '| **total** | **%s** | | |\n' "$(human "$total")"
if [[ -n "$per_round" ]]; then
  printf '\nReview tokens per round: %s\n' "$per_round"
fi
