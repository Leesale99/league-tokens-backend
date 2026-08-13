#!/usr/bin/env bash
# Usage: dispatch.sh [--create-only] <issue> <role> <brief-path>
# §4.4 dispatch primitive — runs ONE headless role dispatch inside the
# issue's long-lived named sandbox. Host-side: needs the sbx CLI and the
# loaded pi template image (see v2/README.md prerequisites).
#
#  1. reads the role spec (mounts, network allow-list, image) — enforced
#     here, documented in v2/README.md
#  2. creates the sandbox `issue-<N>-<role>` if absent, applying the
#     role's network policy
#  3. `sbx exec pi -p @brief "<role prompt>" --mode json`, streaming the
#     event log to docs/issue-workflows/<N>/agents/<topic>.jsonl
#  4. on exit updates workflow.json (agent state + telemetry) and prints
#     a five-line summary + the next command
#
# --create-only: sandbox creation + model-catalog warm-up only. research.sh
# pre-creates each role's sandbox once (sequentially) so parallel
# dispatches of the same role can never race on `sbx create`.

set -euo pipefail

create_only=0
if [[ "${1:-}" == "--create-only" ]]; then create_only=1; shift; fi
issue="${1:?issue number is required}"
role="${2:?role is required}"
brief="${3:?brief path is required}"

repo_root="$(git rev-parse --show-toplevel)"
run_dir="$repo_root/docs/issue-workflows/$issue"
research_dir="$run_dir/research"
# topic id: the topic-dir slug for research briefs (research/<NN>-<slug>/brief.md),
# or the brief filename minus .md for phase-level briefs (e.g. the synthesis brief).
if [[ "$(basename "$brief")" == "brief.md" ]]; then
  topic="$(basename "$(dirname "$brief")")"
else
  topic="$(basename "$brief" .md)"
fi
sandbox="issue-$issue-$role"
IMG="lt/pi-base:spike"          # built + loaded on the host (Phase 0 spike); per-role layers land in Task 4.3
PROVIDER="opencode-go"
MODEL="deepseek-v4-flash"
vault="${LEAGUE_TOKENS_VAULT:-$HOME/Projects/vaults/league-tokens}"

die() { printf 'dispatch: %s\n' "$*" >&2; exit 1; }

# ---- role spec: primary workspace (the only rw path), extra :ro mounts,
# ---- network allow-list, and the expected report path. Enforced here; the
# ---- table lives in scripts/issue-workflow/v2/README.md. Every role gets
# ---- the model endpoints; role-specific hosts are added below. The primary
# ---- is a host path mounted rw, shadowing the :ro repo mount, so an agent
# ---- can write only its own artifact.
case "$role" in
  repo-researcher)
    primary="$research_dir"; extras=("$repo_root:ro")
    nets=(opencode.ai pi.dev); report="$research_dir/$topic/report.md" ;;
  docs-researcher)
    primary="$research_dir"; extras=("$repo_root:ro")
    nets=(opencode.ai pi.dev context7.com); report="$research_dir/$topic/report.md" ;;
  web-researcher)
    primary="$research_dir"; extras=("$repo_root:ro")
    nets=(opencode.ai pi.dev api.openai.com); report="$research_dir/$topic/report.md" ;;
  kb-researcher)
    primary="$research_dir"; extras=("$repo_root:ro" "$vault:ro")
    nets=(opencode.ai pi.dev); report="$research_dir/$topic/report.md" ;;
  context-synthesizer)
    primary="$run_dir"; extras=("$repo_root:ro")
    nets=(opencode.ai pi.dev); report="$run_dir/context.md" ;;
  plan-critic)
    primary="$run_dir"; extras=("$repo_root:ro")
    nets=(opencode.ai pi.dev); report="$run_dir/plan-critic.md" ;;
  *) die "unknown role '$role' — see the role table in scripts/issue-workflow/v2/README.md" ;;
esac

# kb-researcher needs the vault; fail loudly when it is missing.
if [[ "$role" == "kb-researcher" ]] && [[ ! -d "$vault" ]]; then
  die "vault not found at $vault (set LEAGUE_TOKENS_VAULT)"
fi

# ---- 1. network policy (global allow-list; idempotent) ----
policy="$(sbx policy ls 2>/dev/null || true)"
for host in "${nets[@]}"; do
  if ! grep -q "$host" <<<"$policy"; then
    sbx policy allow network "$host" >/dev/null
    policy="$(sbx policy ls 2>/dev/null || true)"
  fi
done

# ---- 2. sandbox: create once per issue+role, then reuse ----
if ! sbx ls 2>/dev/null | awk -v n="$sandbox" '$1 == n {found=1} END {exit !found}'; then
  mkdir -p "$primary"
  sbx create --template "$IMG" --name "$sandbox" shell "$research_dir" "${extras[@]}" >/dev/null
  # create registers the sandbox asynchronously — retry the ls check.
  found=0
  for _ in $(seq 1 10); do
    if sbx ls 2>/dev/null | awk -v n="$sandbox" '$1 == n {found=1} END {exit !found}'; then
      found=1; break
    fi
    sleep 1
  done
  [[ "$found" == 1 ]] || die "sandbox $sandbox did not appear after create"
  # warm the model catalog once per sandbox (pi.dev fetch, first run only).
  sbx exec "$sandbox" pi list-models "$MODEL" >/dev/null 2>&1 \
    || sbx exec "$sandbox" pi update >/dev/null 2>&1 || true
fi

if [[ "$create_only" == 1 ]]; then
  printf 'sandbox ready: %s\n' "$sandbox"
  exit 0
fi

[[ -f "$brief" ]] || die "brief not found: $brief"

# ---- 3. headless dispatch (event log captured on the host) ----
log="$run_dir/agents/$topic.jsonl"
mkdir -p "$run_dir/agents"
role_file="$repo_root/scripts/issue-workflow/v2/roles/$role.md"
[[ -f "$role_file" ]] || die "role contract missing: $role_file"
message="Issue #$issue — run the $role role contract at $role_file; follow it and the attached brief exactly. Write your report, then stop."

t0="$(date +%s.%N)"
set +e
sbx exec -w "$repo_root" "$sandbox" pi -p "@$brief" "$message" --mode json \
  --provider "$PROVIDER" --model "$MODEL" >"$log" 2>"$log.err"
code=$?
set -e
t1="$(date +%s.%N)"
wall="$(awk "BEGIN{printf \"%.1f\", $t1 - $t0}")"

# ---- verdict: pi exits 0 even on model failure — the log is authoritative
if grep -q '"stopReason":"error"' "$log"; then
  state="failed"; reason="model error (stopReason:error) — log: agents/$topic.jsonl"
elif [[ "$code" -ne 0 ]]; then
  state="failed"; reason="pi exit $code — stderr: agents/$topic.jsonl.err"
elif [[ -f "$report" ]]; then
  state="reported"; reason="report: ${report#"$run_dir"/}"
else
  state="failed"; reason="no report at ${report#"$run_dir"/} — log: agents/$topic.jsonl"
fi

tokens="$(jq -r 'select(.type=="message_end") | .message.usage.totalTokens // empty' "$log" 2>/dev/null \
  | awk '{s += $1} END {print s + 0}')"

# ---- 4. workflow.json: agent state + telemetry (serialized via lock) ----
[[ -f "$run_dir/workflow.json" ]] || die "workflow.json missing — run research.sh <issue> first"
# Serialize concurrent agent-state updates via flock (auto-released on exit,
# including on set -e death — no stale locks).
exec 9>"$run_dir/.workflow.lock"
flock 9
tmp="$run_dir/workflow.json.tmp.$$"
# self-register the agent entry when it does not exist yet (standalone
# dispatches of phase-level roles such as context-synthesizer).
jq --arg topic "$topic" --arg role "$role" --arg sandbox "$sandbox" \
   --arg report "${report#"$run_dir"/}" \
   '.phases.research.agents[$topic] //= {role: $role, sandbox: $sandbox, report: $report}' \
   "$run_dir/workflow.json" >"$tmp"
mv "$tmp" "$run_dir/workflow.json"
jq --arg topic "$topic" --arg state "$state" --arg reason "$reason" \
   --argjson tokens "${tokens:-0}" --argjson wall "$wall" \
   '.phases.research.agents[$topic] |= (.state = $state | .reason = $reason | .telemetry = {tokens: $tokens, wall_seconds: $wall})' \
   "$run_dir/workflow.json" >"$tmp"
mv "$tmp" "$run_dir/workflow.json"
rm -f "$tmp"

# ---- five-line summary + next command
printf 'dispatch:  issue #%s · %s · %s\n' "$issue" "$role" "$topic"
printf 'sandbox:   %s\n' "$sandbox"
printf 'result:    %s · %s s · %s tokens\n' "$state" "$wall" "$tokens"
printf 'log:       docs/issue-workflows/%s/agents/%s.jsonl\n' "$issue" "$topic"
printf 'next:      /issue-research %s\n' "$issue"
if [[ "$state" == "failed" ]]; then printf 'reason:    %s\n' "$reason"; fi
