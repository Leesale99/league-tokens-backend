#!/usr/bin/env bash
# Task 4.1 acceptance runner — HOST ONLY (sbx CLI + Docker Desktop + keys).
# Proves the five-reviewer final review headlessly through the real
# dispatch machinery (real model calls):
#
#   1. image rebuild + template load (bakes the golang-* skills — parity
#      with CI's review.yml, which clones samber/cc-skills-golang)
#   2. worktree on feat/999-smoke-review with a KNOWN-BUGGY Go file
#      committed (swallowed os.Open error → nil deref; unchecked slice
#      index; no tests)
#   3. review.sh dispatches all five focuses in parallel (correctness,
#      quality, quality-depth, security, requirements) with the matching
#      --skill args; every report lands at reviews/<focus>.md
#   4. findings quality: correctness MUST flag the planted bugs
#   5. skills actually loaded: /opt/cc-skills-golang present in the
#      sandbox AND the skill name appears in the session JSONL
#   6. workflow.json: review phase gated, agents reported, telemetry set
#   7. main checkout untouched
#
# Prints the cleanup command; does not remove sandboxes (Task 5.2).
# Never prints or persists secret values.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_DIR="$(dirname "$SPIKE_DIR")"
REPO="$(dirname "$(dirname "$(dirname "$V2_DIR")")")"
IMG="lt/pi-base:spike"
N=999
SLUG="smoke-review"
WT="$REPO/.worktrees/issue-$N"
RUN_DIR="$(bash "$V2_DIR/run_dir.sh" "$N")"
OUT="${OUT:-$SPIKE_DIR/out/review-test}"

log() { printf '\n=== %s\n' "$*"; }
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker not found on the host"
command -v sbx >/dev/null 2>&1 || fail "sbx not found on the host"
mkdir -p "$OUT"
main_head_before="$(git -C "$REPO" rev-parse HEAD)"
main_status_before="$(git -C "$REPO" status --porcelain)"

log "0. image (rebuild + load: bakes golang-* skills at /opt/cc-skills-golang)"
docker build -t "$IMG" -f "$V2_DIR/templates/base.Dockerfile" "$REPO" >"$OUT/build.log" 2>&1
docker image save "$IMG" -o "$OUT/pi-base.tar"
sbx template load "$OUT/pi-base.tar" >"$OUT/template-load.log" 2>&1
pass "image rebuilt and loaded"

log "1. issue scaffold (test issue 999: issue.md + track M workflow.json)"
rm -rf "$RUN_DIR"
"$V2_DIR/worktree.sh" "$N" remove >/dev/null 2>&1 || true
rm -rf "$WT"
mkdir -p "$RUN_DIR"
printf '# Smoke review issue 999\n\nKnown-buggy Go code for the Task 4.1 acceptance test.\n' > "$RUN_DIR/issue.md"
"$V2_DIR/mark.sh" "$N" track M "review acceptance" >/dev/null
pass "workflow.json created (track M)"

log "2. worktree + planted bugs"
# Sync the review diff base: reviewers diff origin/main...HEAD; the fetch
# guarantees the ref exists (three-dot diff = our commits only, whatever
# the remote truth is).
git -C "$REPO" fetch --quiet origin main 2>/dev/null || true
"$V2_DIR/worktree.sh" "$N" "$SLUG" >/dev/null
mkdir -p "$WT/internal/smokerev"
cat > "$WT/internal/smokerev/bugs.go" <<'BUGS'
// Package smokerev carries deliberately planted bugs for the Task 4.1
// acceptance test — reviewers MUST flag them.
package smokerev

import (
	"fmt"
	"os"
)

// ReadFirst returns the first line of path.
// BUG (planted): os.Open's error is swallowed; f may be nil when it fails.
func ReadFirst(path string) (string, error) {
	f, _ := os.Open(path)
	defer f.Close()
	var line string
	_, err := fmt.Fscanln(f, &line)
	if err != nil {
		return "", err
	}
	return line, nil
}

// Head returns the first element of list.
// BUG (planted): panics on an empty list — no length check.
func Head(list []string) string {
	return list[0]
}
BUGS
git -C "$WT" -c user.name="Aleksandar Radovanovic" -c user.email="aleksrdvn@192.168.1.5" add internal/smokerev/bugs.go
git -C "$WT" -c user.name="Aleksandar Radovanovic" -c user.email="aleksrdvn@192.168.1.5" commit -q -m "test: plant known review bugs (#999, acceptance)"
head_under_review="$(git -C "$WT" rev-parse HEAD)"
pass "worktree committed at $head_under_review"

log "3. review.sh — five reviewers in parallel (real model)"
# capture-then-tail: a pipe to `tail` would SIGPIPE-kill review.sh mid-wait
# when the tail exits early (the acceptance-batch lesson)
"$V2_DIR/review.sh" "$N" >"$OUT/review.log" 2>&1 || true
tail -12 "$OUT/review.log"

log "4. reports + reviewed_head frontmatter"
for focus in correctness quality quality-depth security requirements; do
  r="$RUN_DIR/reviews/$focus.md"
  [[ -f "$r" ]] || fail "missing report: $r"
  grep -q '^reviewed_head:' "$r" || fail "$r has no reviewed_head frontmatter line"
  pass "$focus.md ($(wc -l < "$r") lines, reviewed_head: $(sed -n 's/^reviewed_head: *//p' "$r" | head -1))"
done

log "5. findings quality — correctness must flag the planted bugs"
grep -qiE 'ReadFirst|Head|os\.Open|swallow' "$RUN_DIR/reviews/correctness.md" \
  || fail "correctness.md does not mention the planted bugs — parity not proven"
pass "correctness.md flags the planted bugs"

log "6. skills baked + actually loaded"
sbx exec "issue-$N-reviewer-correctness" \
  test -d /opt/cc-skills-golang/skills/golang-error-handling \
  || fail "golang-error-handling not baked into the sandbox"
pass "skills baked at /opt/cc-skills-golang"
grep -q 'golang-error-handling' "$RUN_DIR/agents/correctness.jsonl" \
  || fail "session JSONL does not reference the skill — --skill may not be loading"
pass "golang-error-handling referenced in the correctness session log"

log "7. workflow.json state + telemetry"
state="$(jq -r '.phases.review.state' "$RUN_DIR/workflow.json")"
[[ "$state" == "gated" ]] || fail "review phase is '$state', expected gated"
n_reported="$(jq -r '[.phases.review.agents[] | select(.state == "reported")] | length' "$RUN_DIR/workflow.json")"
[[ "$n_reported" == "5" ]] || fail "only $n_reported/5 reviewers reported"
tokens="$(jq -r '.telemetry.review.tokens // 0' "$RUN_DIR/workflow.json")"
[[ "$tokens" -gt 0 ]] || fail "telemetry.review.tokens is 0"
pass "phase gated · $n_reported/5 reported · $tokens tokens"

log "8. main checkout untouched"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$main_head_before" ]] || fail "main HEAD moved"
[[ "$(git -C "$REPO" status --porcelain)" == "$main_status_before" ]] || fail "main checkout dirty"
pass "main checkout untouched"

printf '\n=== review acceptance PASSED ===\n'
printf 'cleanup (Task 5.2 leaves sandboxes running; this is the manual command):\n'
# shellcheck disable=SC2016  # literal shell snippet printed for the user
printf '  for r in correctness quality quality-depth security requirements; do sbx rm --force issue-%s-reviewer-"$r"; done\n' "$N"
printf '  %s/worktree.sh %s remove\n' "$V2_DIR" "$N"
