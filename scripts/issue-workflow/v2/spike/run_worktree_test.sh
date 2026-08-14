#!/usr/bin/env bash
# Task 3.1 acceptance runner — HOST ONLY (sbx CLI + Docker Desktop + the
# loaded pi template). Proves the worktree plumbing end to end:
#
#   1. rebuild + load the base image (bakes git identity + safe.directory)
#   2. worktree.sh creates .worktrees/issue-999 on feat/999-<slug>
#   3. dispatch.sh --create-only spawns the task-implementer sandbox with
#      the worktree rw + .git rw + run dir ro mounts
#   4. inside the sandbox: no credentials (env), push fails (no network),
#      a commit lands in the worktree
#   5. host side: commit visible in the host worktree; main checkout's
#      working tree and HEAD untouched
#
# Prints the cleanup command; does not remove the sandbox (cleanup stays at
# Task 5.2). Never prints or persists secret values.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_DIR="$(dirname "$SPIKE_DIR")"
REPO="$(dirname "$(dirname "$(dirname "$V2_DIR")")")"
IMG="lt/pi-base:spike"
N=999
SLUG="worktree-test"
WT="$REPO/.worktrees/issue-$N"
SB="issue-$N-task-implementer"
OUT="${OUT:-$SPIKE_DIR/out/worktree-test}"
RUN_DIR="$REPO/docs/issue-workflows/$N"

log() { printf '\n=== %s\n' "$*"; }
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker not found on the host"
command -v sbx >/dev/null 2>&1 || fail "sbx not found on the host (brew install docker/tap/sbx)"

mkdir -p "$OUT"
main_head_before="$(git -C "$REPO" rev-parse HEAD)"
main_status_before="$(git -C "$REPO" status --porcelain)"

log "1. image rebuild + load"
docker build -t "$IMG" -f "$V2_DIR/templates/base.Dockerfile" "$REPO" >"$OUT/build.log" 2>&1
docker image save "$IMG" -o "$OUT/pi-base.tar"
sbx template load "$OUT/pi-base.tar" >"$OUT/template-load.log" 2>&1
pass "image built + loaded"

log "2. worktree.sh"
mkdir -p "$RUN_DIR" && echo "# test" > "$RUN_DIR/issue.md"
WT_OUT="$("$V2_DIR/worktree.sh" "$N" "$SLUG")"
[[ "$WT_OUT" == "$WT" ]] || fail "worktree path mismatch: $WT_OUT"
[[ -d "$WT" ]] || fail "worktree dir missing"
WT_BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
[[ "$WT_BRANCH" == "feat/$N-$SLUG" ]] || fail "worktree on '$WT_BRANCH'"
pass "worktree on feat/$N-$SLUG"

log "3. sandbox create (implementer mounts)"
"$V2_DIR/dispatch.sh" --create-only "$N" task-implementer "$RUN_DIR/tasks/01-x.md" >"$OUT/create.log" 2>&1
sbx ls 2>/dev/null | awk -v n="$SB" '$1 == n {found=1} END {exit !found}' \
  || fail "sandbox $SB not present"
pass "sandbox $SB ready"

log "4a. no REAL credentials in the sandbox (env — sbx proxy placeholders allowed)"
# sbx injects proxy-managed placeholders (gho_sbxproxymanaged…, sbx-cs-…)
# and SSH-gateway plumbing by design; the real secrets never enter the
# sandbox. Flag only secret-looking values that are NOT the proxy pattern.
if sbx exec "$SB" env 2>"$OUT/env.err" | awk -F= '
    tolower($1) ~ /token|key|secret|cred|ssh|auth/ {
      v = substr($0, index($0, "=") + 1)
      w = tolower(v)
      if (w == "" || w ~ /sbxproxymanaged|proxy-managed|sbx-cs-|gateway|\.sock|^(apikey|oauth|none)$/) next
      print
    }' | grep -q .; then
  fail "credential-looking env vars leaked into the sandbox: $(sbx exec "$SB" env 2>/dev/null | awk -F= '
    tolower($1) ~ /token|key|secret|cred|ssh|auth/ {
      v = substr($0, index($0, "=") + 1)
      w = tolower(v)
      if (w == "" || w ~ /sbxproxymanaged|proxy-managed|sbx-cs-|gateway|\.sock|^(apikey|oauth|none)$/) next
      print
    }' | tr '\n' ' ')"
fi
pass "env clean (proxy placeholders only)"

log "4b. deliberate push fails (no github.com in the allow-list, no creds)"
if sbx exec "$SB" bash -lc "cd '$WT' && git push -u origin HEAD" >"$OUT/push.log" 2>&1; then
  fail "push unexpectedly succeeded"
fi
pass "push failed as required ($(tail -1 "$OUT/push.log" | head -c 120))"

log "4c. commit from inside the sandbox"
sbx exec "$SB" bash -lc "cd '$WT' && printf 'round-trip\\n' >> .worktree-test && git add .worktree-test && git commit -q -m 'test(worktree): sandbox commit round-trip (#$N)' && git log --oneline -1" >"$OUT/commit.log" 2>&1
grep -q "sandbox commit round-trip" "$OUT/commit.log" || fail "commit not created: $(cat "$OUT/commit.log")"
pass "commit created inside the sandbox"

log "5a. commit visible in the host worktree"
git -C "$WT" log --oneline -1 | grep -q "sandbox commit round-trip" || fail "host worktree missing the commit"
pass "host worktree sees the commit"

log "5b. main checkout untouched"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$main_head_before" ]] || fail "main HEAD moved!"
[[ "$(git -C "$REPO" status --porcelain)" == "$main_status_before" ]] || fail "main working tree changed!"
[[ ! -f "$REPO/.worktree-test" ]] || fail "test file leaked into the main checkout"
pass "main checkout HEAD + working tree unchanged"

log "summary"
printf '  worktree:   %s (feat/%s-%s)\n' "$WT" "$N" "$SLUG"
printf '  sandbox:    %s (kept for inspection)\n' "$SB"
printf '  cleanup:    sbx rm --force %s; %s %s remove\n' "$SB" "$V2_DIR/worktree.sh" "$N"
