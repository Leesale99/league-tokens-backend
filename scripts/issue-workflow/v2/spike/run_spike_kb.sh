#!/usr/bin/env bash
# Phase 0 Task 0.4 spike runner — vault :ro + context7 from a sandbox.
# Runs ON THE HOST. Demonstrates: (1) the league-tokens vault mounted :ro and
# read from inside a sandbox; (2) a context7 API query from inside the sandbox
# using the placeholder API key (host-side proxy swaps the real key); (3) the
# exact `sbx policy allow network` arguments for the dispatch script.
# Writes evidence under docs/issue-workflows/spike/.

set -euo pipefail

REPO="/Users/aleksrdvn/Projects/league-tokens/backend"
VAULT="${LEAGUE_TOKENS_VAULT:-$HOME/Projects/vaults/league-tokens}"
OUT="$REPO/docs/issue-workflows/spike"
IMG="lt/pi-base:spike"
NAME="lt-spike-kb"

mkdir -p "$OUT/work"
log() { printf '[spike-kb] %s\n' "$*" >&2; }

command -v sbx >/dev/null 2>&1 || { echo "sbx CLI not found on the host." >&2; exit 2; }
[[ -d "$VAULT" ]] || { echo "Vault not found: $VAULT" >&2; exit 2; }

log "network allow-list for context7 (exact args for dispatch.sh)"
sbx policy ls | grep -q "context7.com" \
  || sbx policy allow network context7.com >"$OUT/policy-allow-context7.txt" 2>&1 || true

log "create sandbox: scratch primary + vault :ro"
sbx rm --force "$NAME" >/dev/null 2>&1 || true
sbx create --template "$IMG" --name "$NAME" shell "$OUT/work" "$VAULT:ro" \
  >"$OUT/create-kb.log" 2>&1
sbx ls 2>/dev/null | grep -q "$NAME" || { echo "create failed — see $OUT/create-kb.log" >&2; exit 2; }

log "vault read + ro enforcement"
# shellcheck disable=SC2016 # $VAULT expands inside the sandbox
sbx exec "$NAME" bash -lc "printf 'vault top-level entries:\\n'; ls '$VAULT' | head -6; printf '\\nINDEX.md head:\\n'; head -6 '$VAULT/INDEX.md'" \
  >"$OUT/vault-read.txt" 2>&1 || true
# shellcheck disable=SC2016
sbx exec "$NAME" bash -lc "touch '$VAULT/spike-ro-test'; echo write_to_vault_exit=\$?" \
  >"$OUT/vault-ro.txt" 2>&1 || true

log "context7 query from inside the sandbox (placeholder key -> proxy swap)"
# shellcheck disable=SC2016 # $CONTEXT7_API_KEY expands inside the sandbox
sbx exec "$NAME" bash -lc 'printf "CONTEXT7_API_KEY=%s len=%s\n" "${CONTEXT7_API_KEY:0:8}" "${#CONTEXT7_API_KEY}"; curl -s -m 30 -w "\nHTTP %{http_code}\n" "https://context7.com/api/v2/libs/search?query=express&libraryName=Express.js" -H "Authorization: Bearer $CONTEXT7_API_KEY" | head -c 600' \
  >"$OUT/context7-query.txt" 2>&1 || true

log "egress isolation probes (unrelated domains should be blocked)"
# shellcheck disable=SC2016
sbx exec "$NAME" bash -lc 'for d in example.org sbx.sh; do printf "%s -> " "$d"; curl -s -m 8 -o /dev/null -w "%{http_code}" "https://$d" 2>&1 || echo -n "ERR"; echo; done' \
  >"$OUT/egress-probes.txt" 2>&1 || true

log "record policy"
sbx policy ls >"$OUT/policy-context7.txt" 2>&1 || true
sbx ls >"$OUT/sbx-ls-kb.txt" 2>&1 || true
log "done — see $OUT"
