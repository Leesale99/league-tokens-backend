#!/usr/bin/env bash
# Task 4.2 acceptance runner — HOST ONLY (sbx CLI + Docker Desktop + keys).
# Proves incremental re-review through the real dispatch machinery (real
# model calls), building on Task 4.1's review.sh:
#
#   round 1  five reviewers on a KNOWN-BUGGY file (swallowed os.Open error
#            -> nil deref; unchecked slice index; no tests). correctness
#            MUST come back red.
#   round 2  fix bug A, but ALSO plant a REGRESSION (new swallowed error)
#            in the fix commit; review.sh --re-review re-dispatches ONLY
#            the red focuses against reviewed_head..HEAD. Assertions:
#            - only red focuses dispatched (correctness at minimum)
#            - round-2 correctness tokens < round-1 correctness tokens
#              (measurable savings — telemetry.review.rounds)
#            - the planted REGRESSION is still caught (parity: a second
#              round still finds new bugs)
#   round 3  fix the remaining bug + the regression; --re-review again;
#            correctness goes green
#   finalize review.sh --finalize writes reviews/summary.md with the Task
#            0.2 gate frontmatter; check_review_gate.sh exits 0
#
# Prints the cleanup command; does not remove sandboxes (Task 5.2).
# Never prints or persists secret values.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_DIR="$(dirname "$SPIKE_DIR")"
REPO="$(dirname "$(dirname "$(dirname "$V2_DIR")")")"
IMG="lt/pi-base:spike"
N=999
SLUG="smoke-rereview"
WT="$REPO/.worktrees/issue-$N"
RUN_DIR="$(bash "$V2_DIR/run_dir.sh" "$N")"
OUT="${OUT:-$SPIKE_DIR/out/rereview-test}"

log() { printf '\n=== %s\n' "$*"; }
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }
gitid() { git -C "$WT" -c user.name="Aleksandar Radovanovic" -c user.email="aleksrdvn@192.168.1.5" "$@"; }

command -v docker >/dev/null 2>&1 || fail "docker not found on the host"
command -v sbx >/dev/null 2>&1 || fail "sbx not found on the host"
mkdir -p "$OUT"
main_head_before="$(git -C "$REPO" rev-parse HEAD)"
main_status_before="$(git -C "$REPO" status --porcelain)"

log "0. image (rebuild + load)"
docker build -t "$IMG" -f "$V2_DIR/templates/base.Dockerfile" "$REPO" >"$OUT/build.log" 2>&1
docker image save "$IMG" -o "$OUT/pi-base.tar"
sbx template load "$OUT/pi-base.tar" >"$OUT/template-load.log" 2>&1

log "1. issue scaffold (test issue 999: issue.md + track M)"
rm -rf "$RUN_DIR"
"$V2_DIR/worktree.sh" "$N" remove >/dev/null 2>&1 || true
rm -rf "$WT"
mkdir -p "$RUN_DIR"
printf '# Smoke re-review issue 999\n\nRound-trip for the Task 4.2 acceptance test.\n' > "$RUN_DIR/issue.md"
"$V2_DIR/mark.sh" "$N" track M "rereview acceptance" >/dev/null

log "2. worktree + planted bugs (A: swallowed error, B: unchecked index)"
git -C "$REPO" fetch --quiet origin main 2>/dev/null || true
"$V2_DIR/worktree.sh" "$N" "$SLUG" >/dev/null
mkdir -p "$WT/internal/smokerev"
cat > "$WT/internal/smokerev/bugs.go" <<'BUGS'
package smokerev

import (
	"fmt"
	"os"
)

// ReadFirst returns the first line of path.
// BUG A (planted): os.Open's error is swallowed; f may be nil.
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
// BUG B (planted): panics on an empty list — no length check.
func Head(list []string) string {
	return list[0]
}
BUGS
gitid add internal/smokerev/bugs.go
gitid commit -q -m "test: plant known review bugs (#999, acceptance r1)"

log "3. round 1 — five reviewers in parallel (real model)"
"$V2_DIR/review.sh" "$N" >"$OUT/round1.log" 2>&1 || true
tail -9 "$OUT/round1.log"
[[ "$(jq -r '.phases.review.round' "$RUN_DIR/workflow.json")" == "1" ]] || fail "round 1 not recorded"
grep -q '^status: red' "$RUN_DIR/reviews/correctness.md" \
  || fail "correctness is not red in round 1 — planted bugs missed: $(head -6 "$RUN_DIR/reviews/correctness.md")"
pass "round 1 gated; correctness red"

log "4. fix BUG A + plant a REGRESSION (BUG C) in the same commit"
cat > "$WT/internal/smokerev/bugs.go" <<'BUGS'
package smokerev

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// ReadFirst returns the first line of path.
// FIXED: the open error is now checked and wrapped.
func ReadFirst(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	line, err := bufio.NewReader(f).ReadString('\n')
	if err != nil && !strings.Contains(err.Error(), "EOF") {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

// Head returns the first element of list.
// BUG B (planted, UNFIXED): panics on an empty list.
func Head(list []string) string {
	return list[0]
}

// Tail returns the last element of list.
// BUG C (planted REGRESSION in the fix commit): panics on an empty list.
func Tail(list []string) string {
	return list[len(list)-1]
}
BUGS
gitid add internal/smokerev/bugs.go
gitid commit -q -m "test: fix bug A, plant regression C (#999, acceptance r2)"

log "5. round 2 — --re-review (only red focuses; incremental diff)"
"$V2_DIR/review.sh" "$N" --re-review >"$OUT/round2.log" 2>&1 || true
tail -9 "$OUT/round2.log"
[[ "$(jq -r '.phases.review.round' "$RUN_DIR/workflow.json")" == "2" ]] || fail "round 2 not recorded"
# data-driven invariant: round 2 re-dispatches EXACTLY the round-1 red set
r1_red="$(jq -r '[.telemetry.review.rounds[0].agents | to_entries[] | select(.value.status == "red") | .key] | sort | join(",")' "$RUN_DIR/workflow.json")"
r2_focuses="$(jq -r '[.telemetry.review.rounds[1].dispatched[]] | sort | join(",")' "$RUN_DIR/workflow.json")"
[[ -n "$r1_red" ]] || fail "no red focuses recorded in the round-1 snapshot"
[[ "$r2_focuses" == "$r1_red" ]] \
  || fail "round 2 must re-dispatch exactly the round-1 red focuses (red: $r1_red, dispatched: $r2_focuses)"
[[ "$r2_focuses" == *"correctness"* ]] || fail "correctness not re-dispatched in round 2"
# measurably fewer tokens: strict for correctness (the planted-bug focus),
# informational for the rest
t1="$(jq -r '.telemetry.review.rounds[0].agents.correctness.tokens' "$RUN_DIR/workflow.json")"
t2="$(jq -r '.telemetry.review.rounds[1].agents.correctness.tokens' "$RUN_DIR/workflow.json")"
[[ "$t1" =~ ^[0-9]+$ && "$t2" =~ ^[0-9]+$ && "$t2" -lt "$t1" ]] \
  || fail "round 2 not cheaper for correctness: round1=$t1 tokens, round2=$t2"
for f in ${r1_red//,/ }; do
  # bracket syntax: focus names contain dashes (jq would parse .agents.quality-depth as arithmetic)
  a="$(jq -r --arg f "$f" '.telemetry.review.rounds[0].agents[$f].tokens' "$RUN_DIR/workflow.json")"
  b="$(jq -r --arg f "$f" '.telemetry.review.rounds[1].agents[$f].tokens' "$RUN_DIR/workflow.json")"
  printf '  token note: %s round1=%s round2=%s (%s)\n' "$f" "$a" "$b" "$([ "$b" -lt "$a" ] && echo cheaper || echo NOT cheaper)"
done
pass "round 2 incremental (red set: $r1_red); correctness $t1 -> $t2 tokens"
grep -qiE 'Tail|BUG C|regression' "$RUN_DIR/reviews/correctness.md" \
  || fail "round 2 missed the planted regression (Tail)"
grep -q '^status: red' "$RUN_DIR/reviews/correctness.md" || fail "correctness should stay red in round 2"
pass "planted regression caught; correctness still red"

log "6. fix BUG B + BUG C; round 3 --re-review"
python3 - <<'PYEOF'
p = "/Users/aleksrdvn/Projects/league-tokens/backend/.worktrees/issue-999/internal/smokerev/bugs.go"
s = open(p).read()
s = s.replace("""// Head returns the first element of list.
// BUG B (planted, UNFIXED): panics on an empty list.
func Head(list []string) string {
	return list[0]
}""", """// Head returns the first element of list.
func Head(list []string) string {
	if len(list) == 0 {
		return ""
	}
	return list[0]
}""")
s = s.replace("""// Tail returns the last element of list.
// BUG C (planted REGRESSION in the fix commit): panics on an empty list.
func Tail(list []string) string {
	return list[len(list)-1]
}""", """// Tail returns the last element of list.
func Tail(list []string) string {
	if len(list) == 0 {
		return ""
	}
	return list[len(list)-1]
}""")
open(p, "w").write(s)
PYEOF
gitid add internal/smokerev/bugs.go
gitid commit -q -m "test: fix bugs B and C (#999, acceptance r3)"
"$V2_DIR/review.sh" "$N" --re-review >"$OUT/round3.log" 2>&1 || true
tail -9 "$OUT/round3.log"
[[ "$(jq -r '.phases.review.round' "$RUN_DIR/workflow.json")" == "3" ]] || fail "round 3 not recorded"
grep -q '^status: green' "$RUN_DIR/reviews/correctness.md" || fail "correctness not green after round 3"
pass "round 3 green"

log "7. --finalize + gate"
"$V2_DIR/review.sh" "$N" --finalize >"$OUT/finalize.log" 2>&1 || fail "finalize failed: $(tail -2 "$OUT/finalize.log")"
grep -q '^status: green' "$RUN_DIR/reviews/summary.md" || fail "summary.md not green"
grep -q '^blocking_unresolved: 0' "$RUN_DIR/reviews/summary.md" || fail "summary.md blocking_unresolved != 0"
"$REPO/scripts/issue-workflow/check_review_gate.sh" "$N" >"$OUT/gate.log" 2>&1 \
  || fail "review gate not green: $(cat "$OUT/gate.log")"
pass "summary.md green; check_review_gate.sh exits 0"

log "8. main checkout untouched"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$main_head_before" ]] || fail "main HEAD moved"
[[ "$(git -C "$REPO" status --porcelain)" == "$main_status_before" ]] || fail "main checkout dirty"
pass "main checkout untouched"

printf '\n=== re-review acceptance PASSED (rounds 1→2→3, tokens %s → %s) ===\n' "$t1" "$t2"
printf 'cleanup (Task 5.2 leaves sandboxes running; this is the manual command):\n'
# shellcheck disable=SC2016  # literal shell snippet printed for the user
printf '  for r in correctness quality quality-depth security requirements; do sbx rm --force issue-%s-reviewer-"$r"; done\n' "$N"
printf '  %s/worktree.sh %s remove\n' "$V2_DIR" "$N"
