#!/usr/bin/env bash
# Phase 1 Task 1.2 acceptance runner — runs ON THE HOST (sbx CLI + Docker
# Desktop + the lt/pi-base:spike template). Creates a throwaway test issue
# with four research briefs (one per role), runs research.sh, and asserts
# the Task 1.2 acceptance criteria:
#   - four sandboxes run concurrently (sbx ls shows issue-999-<role> ×4)
#   - reports and workflow.json land correctly (phase gated, 4 agents
#     reported, telemetry totals)
# Evidence is printed; sandboxes are left running for inspection (clean up
# with: sbx rm --force issue-999-repo-researcher issue-999-docs-researcher
# issue-999-web-researcher issue-999-kb-researcher).

set -euo pipefail

REPO="/Users/aleksrdvn/Projects/league-tokens/backend"
N=999
run_dir="$(bash "$V2_DIR/run_dir.sh" "$N")"
research_dir="$run_dir/research"

command -v sbx >/dev/null 2>&1 || { echo "sbx CLI not found on the host." >&2; exit 2; }
sbx ls 2>/dev/null | grep -q "^lt/pi-base" || true  # template presence is checked by create

log() { printf '[dispatch-test] %s\n' "$*" >&2; }

log "reset test issue #$N (gitignored dir)"
rm -rf "$run_dir"
mkdir -p "$research_dir"/{01-repo-map,02-dep-facts,03-web-angles,04-kb-history} "$run_dir/agents"

log "write four briefs (role on line 1)"
cat >"$research_dir/01-repo-map/brief.md" <<'EOF'
role: repo-researcher
Question: Where does session/token validation live in this repo, and what tests cover it?
Scope: Locate the relevant package(s), entry points, and test files.
Expected sources: CONTEXT.md, docs/adr/, code, tests.
Constraints: read-only; ≤5 findings.
EOF
cat >"$research_dir/02-dep-facts/brief.md" <<'EOF'
role: docs-researcher
Question: What are the main dependencies in go.mod, and what is the current documented version of the largest one via context7?
Scope: go.mod + one context7 query per main dependency.
Expected sources: go.mod, context7.
Constraints: read-only; ≤5 findings; flag version drift.
EOF
cat >"$research_dir/03-web-angles/brief.md" <<'EOF'
role: web-researcher
Question: Find 2–3 recent sources on containerized/sandboxed agent workflows and their failure modes.
Scope: web_search with varied queries; fetch the promising pages.
Expected sources: web articles.
Constraints: label recommendations [non-authoritative]; ≤5 findings.
EOF
vault_path="${LEAGUE_TOKENS_VAULT:-$HOME/Projects/vaults/league-tokens}"
cat >"$research_dir/04-kb-history/brief.md" <<EOF
role: kb-researcher
Question: What does the vault say about the issue workflow or agent-driven development prior art?
Scope: decisions/, lessons/, topics/, archive/ — search for "workflow", "agent", "review".
Expected sources: vault (read-only mount; path: $vault_path).
Constraints: ≤5 findings with vault paths; never write to the vault.
EOF

log "run research.sh $N (creates 4 sandboxes, dispatches ≤4 parallel)"
bash "$REPO/scripts/issue-workflow/v2/research.sh" "$N"

log "assert: four named sandboxes in sbx ls"
for r in repo-researcher docs-researcher web-researcher kb-researcher; do
  sbx ls 2>/dev/null | awk -v n="issue-$N-$r" '$1 == n {found=1} END {exit !found}' \
    || { echo "FAIL: sandbox issue-$N-$r missing" >&2; exit 1; }
  echo "  ok issue-$N-$r"
done

log "assert: four reports landed"
for t in 01-repo-map 02-dep-facts 03-web-angles 04-kb-history; do
  [[ -f "$research_dir/$t/report.md" ]] || { echo "FAIL: $t/report.md missing" >&2; exit 1; }
  echo "  ok research/$t/report.md ($(wc -l <"$research_dir/$t/report.md") lines)"
done

log "assert: workflow.json is gated with 4 reported agents + telemetry"
jq -e '.phases.research.state == "gated"' "$run_dir/workflow.json" >/dev/null \
  || { echo "FAIL: phase not gated" >&2; exit 1; }
jq -e '[.phases.research.agents[] | select(.state == "reported")] | length == 4' "$run_dir/workflow.json" >/dev/null \
  || { echo "FAIL: not all agents reported" >&2; exit 1; }
jq -e '.telemetry.research.dispatches == 4' "$run_dir/workflow.json" >/dev/null \
  || { echo "FAIL: telemetry.dispatches != 4" >&2; exit 1; }

log "synthesize context.md (context-synthesizer dispatch)"
cat >"$run_dir/synthesis-brief.md" <<EOF
Synthesize context.md for issue #$N from research/*/report.md per the context-synthesizer role contract.
EOF
bash "$REPO/scripts/issue-workflow/v2/dispatch.sh" "$N" context-synthesizer "$run_dir/synthesis-brief.md"
[[ -f "$run_dir/context.md" ]] || { echo "FAIL: context.md missing" >&2; exit 1; }
echo "  ok context.md ($(wc -l <"$run_dir/context.md") lines)"

log "finalize the research phase (human approved context.md)"
bash "$REPO/scripts/issue-workflow/v2/research.sh" "$N" --finalize
jq -e '.phases.research.state == "done" and .phase == "plan"' "$run_dir/workflow.json" >/dev/null \
  || { echo "FAIL: research phase not done / next phase not plan" >&2; exit 1; }
echo "  ok phase done, next: plan"

log "assert: zero tmux windows for issue #$N"
if tmux ls 2>/dev/null | grep -q "issue-$N"; then
  echo "FAIL: tmux sessions for issue $N exist" >&2; exit 1
fi
echo "  ok zero tmux"

log "PASS — acceptance criteria met"
printf '\n%-24s %-20s %-9s\n' 'TOPIC' 'ROLE' 'STATE'
jq -r '.phases.research.agents | to_entries[] | [.key, .value.role, .value.state] | @tsv' "$run_dir/workflow.json" \
  | awk -F '\t' '{printf "%-24s %-20s %-9s\n", $1, $2, $3}'
printf 'telemetry: %s tokens · %s s · %s dispatches\n' \
  "$(jq -r '.telemetry.research.tokens' "$run_dir/workflow.json")" \
  "$(jq -r '.telemetry.research.wall_seconds' "$run_dir/workflow.json")" \
  "$(jq -r '.telemetry.research.dispatches' "$run_dir/workflow.json")"
printf '\nEvidence:\n  workflow.json: %s\n  reports:       %s/*/report.md\n  context.md:    %s/context.md\n  event logs:    %s/agents/*.jsonl\n' \
  "$run_dir/workflow.json" "$research_dir" "$run_dir" "$run_dir"
printf '\nCleanup (after inspection): sbx rm --force issue-%s-repo-researcher issue-%s-docs-researcher issue-%s-web-researcher issue-%s-kb-researcher issue-%s-context-synthesizer\n' "$N" "$N" "$N" "$N" "$N"
