#!/usr/bin/env bash
# Phase 0 Task 0.3 spike runner — runs ON THE HOST (macOS + Docker Desktop +
# sbx CLI). Measures: template build time, sandbox create latency, headless
# `pi -p --mode json` inside the sandbox (exit behavior, log streaming), and
# credential-proxy mechanics (placeholder in sandbox env, real key never
# present). Writes measurements and logs under
# docs/issue-workflows/spike/ (gitignored).
#
# Prereqs: sbx installed and logged in; pi authenticated for the provider
# (OPENCODE_API_KEY env, or pi's own credential resolution); Docker Desktop
# running for the template build. Never prints or persists secret values.

set -euo pipefail

REPO="/Users/aleksrdvn/Projects/league-tokens/backend"
OUT="$REPO/docs/issue-workflows/spike"
IMG="lt/pi-base:spike"
NAME="lt-spike-pi"
PROVIDER="opencode-go"
MODEL="deepseek-v4-flash"
API_DOMAIN="opencode.ai"

mkdir -p "$OUT" "$OUT/work"
log() { printf '[spike] %s\n' "$*" >&2; }
dur() { awk "BEGIN{printf \"%.2f\", $2 - $1}"; }

# Preflight: the spike must run on the host (macOS: sbx + Docker Desktop).
command -v sbx >/dev/null 2>&1 || {
  echo "sbx CLI not found on the host." >&2
  echo "Install: brew trust docker/tap && brew install docker/tap/sbx, then sbx login once." >&2
  exit 2
}
command -v docker >/dev/null 2>&1 || {
  echo "docker not found on the host (needed to build the template)." >&2
  exit 2
}

# Resolve the provider key through pi itself (env var or pi credential
# store); pipe straight into the sbx secret store, never into a file or
# stdout. OPENCODE_API_KEY in env wins (matches what the sandbox pi will see).
api_key="${OPENCODE_API_KEY:-$(pi auth print-api-key --provider "$PROVIDER" 2>/dev/null || true)}"
[[ -n "$api_key" ]] || {
  echo "No provider key for $PROVIDER (set OPENCODE_API_KEY or fix pi auth)." >&2
  exit 2
}

log "probes"
sbx --version >"$OUT/probe-sbx-version.txt" 2>&1 || true
sbx policy ls >"$OUT/probe-policy.txt" 2>&1 || true
sbx secret ls >"$OUT/probe-secrets.txt" 2>&1 || true

log "network allow-list: $API_DOMAIN, pi.dev"
if ! grep -q "$API_DOMAIN" "$OUT/probe-policy.txt" 2>/dev/null; then
  sbx policy allow network "$API_DOMAIN" >"$OUT/policy-allow.txt" 2>&1 || true
fi
if ! grep -q "pi.dev" "$OUT/probe-policy.txt" 2>/dev/null; then
  sbx policy allow network pi.dev >>"$OUT/policy-allow.txt" 2>&1 || true
fi

log "credential: custom secret (host store), placeholder inside sandbox"
sbx secret set-custom --host "$API_DOMAIN" --env OPENCODE_API_KEY \
  --value "$api_key" >"$OUT/secret-set.txt" 2>&1 || true
unset api_key

log "template build"
t0=$(date +%s.%N)
docker build -t "$IMG" -f "$REPO/scripts/issue-workflow/v2/templates/base.Dockerfile" "$REPO" \
  >"$OUT/template-build.log" 2>&1
t1=$(date +%s.%N)
docker image save "$IMG" -o "$OUT/work/pi-base.tar"
t2=$(date +%s.%N)
sbx template load "$OUT/work/pi-base.tar" >"$OUT/template-load.log" 2>&1
t3=$(date +%s.%N)

log "create sandbox (repo mounted :ro as extra workspace)"
sbx rm --force "$NAME" >/dev/null 2>&1 || true
t4=$(date +%s.%N)
sbx create --template "$IMG" --name "$NAME" shell "$OUT/work" "$REPO:ro" >"$OUT/create.log" 2>&1
t5=$(date +%s.%N)
sbx ls 2>/dev/null | grep -q "$NAME" || { echo "sandbox $NAME not running after create — see $OUT/create.log" >&2; exit 2; }

log "ensure pi model catalog (first run may fetch from pi.dev)"
sbx exec "$NAME" pi list-models "$MODEL" >"$OUT/sandbox-list-models.txt" 2>&1 \
  || sbx exec "$NAME" pi update >"$OUT/sandbox-pi-update.txt" 2>&1 || true
sbx exec "$NAME" pi list-models "$MODEL" >>"$OUT/sandbox-list-models.txt" 2>&1 || true

log "headless pi -p --mode json (event log captured on host)"
t6=$(date +%s.%N)
set +e
sbx exec -w "$OUT/work" "$NAME" pi -p "@$OUT/brief.md" \
  "Spike: read-only repo research. Follow the brief exactly." \
  --mode json --provider "$PROVIDER" --model "$MODEL" \
  >"$OUT/pi-session.jsonl" 2>"$OUT/pi-stderr.log"
pi_exit=$?
set -e
t7=$(date +%s.%N)

log "sandbox-side probes"
# shellcheck disable=SC2016 # ${OPENCODE_API_KEY} expands inside the sandbox, not here
sbx exec "$NAME" bash -lc 'printf "OPENCODE_API_KEY=%s len=%s\n" "${OPENCODE_API_KEY:0:8}" "${#OPENCODE_API_KEY}"; printf "key-like env vars:\n"; env | cut -d= -f1 | grep -iE "key|token|secret" || true' \
  >"$OUT/sandbox-env.txt" 2>&1 || true
sbx exec "$NAME" bash -lc "touch '$REPO/spike-ro-test'; echo write_to_repo_exit=\$?" \
  >"$OUT/sandbox-ro.txt" 2>&1 || true
sbx exec "$NAME" bash -lc 'pi --version; node --version; git --version; rg --version | head -1; jq --version' \
  >"$OUT/sandbox-toolchain.txt" 2>&1 || true

log "collect"
sbx ls >"$OUT/sbx-ls.txt" 2>&1 || true
jq -n \
  --argjson template_build_s "$(dur "$t0" "$t1")" \
  --argjson image_save_s "$(dur "$t1" "$t2")" \
  --argjson template_load_s "$(dur "$t2" "$t3")" \
  --argjson create_s "$(dur "$t4" "$t5")" \
  --argjson first_pi_exec_s "$(dur "$t6" "$t7")" \
  --argjson pi_exit "$pi_exit" \
  --arg provider "$PROVIDER" --arg model "$MODEL" \
  --arg out "$OUT" \
  '{measurements: {
      template_build_s: $template_build_s,
      image_save_s: $image_save_s,
      template_load_s: $template_load_s,
      create_s: $create_s,
      first_pi_exec_s: $first_pi_exec_s},
    pi: {exit: $pi_exit, provider: $provider, model: $model},
    outputs: $out}' \
  >"$OUT/measurements.json"
log "done — see $OUT"
