#!/usr/bin/env bash
# Task 3.2 acceptance runner — HOST ONLY (sbx CLI + Docker Desktop + keys).
# Executes a TWO-TASK plan fully headless through the real dispatch
# machinery (real model calls), proving:
#
#   1. worktree + implementer sandbox + reviewer sandbox all in place
#   2. task 01: implementer dispatches, reviewer verifies (typecheck +
#      focused test + full suite) and commits `feat: ... (#999, task 01)`
#   3. task 02: same, committing on top (stacked per-task commits)
#   4. task states in workflow.json: {state: done, commit: <sha>} for both
#   5. fix loop: the runner breaks the brief, forces a red review, amends
#      the brief, re-dispatches, and the re-dispatch goes green
#   6. main checkout untouched throughout
#
# Prints the cleanup command; does not remove sandboxes (Task 5.2).
# Never prints or persists secret values.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_DIR="$(dirname "$SPIKE_DIR")"
REPO="$(dirname "$(dirname "$V2_DIR")")"
IMG="lt/pi-base:spike"
N=999
SLUG="smoke-implement"
WT="$REPO/.worktrees/issue-$N"
RUN_DIR="$REPO/docs/issue-workflows/$N"
OUT="${OUT:-$SPIKE_DIR/out/implement-test}"
SB_IMPL="issue-$N-task-implementer"
SB_REV="issue-$N-task-reviewer"

log() { printf '\n=== %s\n' "$*"; }
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker not found on the host"
command -v sbx >/dev/null 2>&1 || fail "sbx not found on the host"
mkdir -p "$OUT"
main_head_before="$(git -C "$REPO" rev-parse HEAD)"
main_status_before="$(git -C "$REPO" status --porcelain)"

log "0. image (rebuild + load: bakes git identity, safe.directory, Go)"
docker build -t "$IMG" -f "$V2_DIR/templates/base.Dockerfile" "$REPO" >"$OUT/build.log" 2>&1
docker image save "$IMG" -o "$OUT/pi-base.tar"
sbx template load "$OUT/pi-base.tar" >"$OUT/template-load.log" 2>&1

log "1. issue scaffold (test issue 999: issue.md, plan.md, two briefs)"
rm -rf "$RUN_DIR" "$WT"
mkdir -p "$RUN_DIR/tasks"
cat > "$RUN_DIR/issue.md" <<'ISSUE'
# Smoke issue 999

Two trivial Go tasks to prove the headless implement/review loop.
ISSUE
cat > "$RUN_DIR/plan.md" <<'PLAN'
# Plan (smoke)

## TL;DR for humans
Two tasks: a Plus helper and a Greet helper, each with a focused test.
PLAN
cat > "$RUN_DIR/tasks/01-smoke-plus.md" <<'BRIEF1'
# Task 01: add smoke Plus helper

## TL;DR for humans
Add a tiny pure Go helper with a passing test to prove the headless loop.

## Description
Create `internal/smoke999/plus.go` with `func Plus(a, b int) int` returning
`a + b`, and `internal/smoke999/plus_test.go` with a table test covering
positive and negative values.

## Context
Repo is Go 1.26; package `github.com/Leesale99/league-tokens-backend`.
Module proxy access is allowed; no vendor dir.

## Acceptance criteria
- [ ] plus.go and plus_test.go exist in internal/smoke999/
- [ ] `go build ./...` passes (typecheck)
- [ ] `go test ./internal/smoke999/...` passes (focused)
- [ ] `go test ./...` passes (full suite)
- [ ] nothing else changed

## Implementation and verification guidance
Write the files, run the three checks above, stage exactly these two files.

## References
Read plan.md / context.md / issue.md from the read-only path only if
essential information is missing from this brief.
BRIEF1
cat > "$RUN_DIR/tasks/02-smoke-greet.md" <<'BRIEF2'
# Task 02: add smoke Greet helper

## TL;DR for humans
Add a second tiny Go helper with a passing test, committing on top of task 01.

## Description
Create `internal/smoke999/greet.go` with `func Greet(name string) string`
returning `"hello, " + name`, and `internal/smoke999/greet_test.go` with a
test for two names.

## Context
Same repo facts as task 01. Task 01's files already exist in this branch.

## Acceptance criteria
- [ ] greet.go and greet_test.go exist in internal/smoke999/
- [ ] `go build ./...` passes
- [ ] `go test ./internal/smoke999/...` passes
- [ ] `go test ./...` passes
- [ ] nothing else changed

## Implementation and verification guidance
Write the files, run the three checks, stage exactly these two files.

## References
Read plan.md / context.md / issue.md from the read-only path only if
essential information is missing from this brief.
BRIEF2

log "2. worktree"
"$V2_DIR/worktree.sh" "$N" "$SLUG" >/dev/null
pass "worktree on feat/$N-$SLUG"

run_task() { # <task-file>
  local task="$1" topic="${1%.md}"
  log "3. task $task — implementer dispatch (real model)"
  "$V2_DIR/mark.sh" "$N" task-run "$task" >/dev/null
  "$V2_DIR/dispatch.sh" "$N" task-implementer "$RUN_DIR/tasks/$task" 2>&1 | tee "$OUT/impl-$topic.log" | grep -E 'result:' || true
  grep -q 'result:    reported' "$OUT/impl-$topic.log" || fail "implementer not reported for $task"

  log "4. task $task — reviewer dispatch (real model)"
  "$V2_DIR/dispatch.sh" "$N" task-reviewer "$RUN_DIR/tasks/$task" 2>&1 | tee "$OUT/rev-$topic.log" | grep -E 'result:' || true
  grep -q 'result:    reported' "$OUT/rev-$topic.log" || fail "reviewer not reported for $task"
  local report="$WT/docs/issue-workflows/$N/reports/$topic.review.md"
  [[ -f "$report" ]] || fail "review report missing: $report"
  head -2 "$report"
  grep -q 'verdict: green' "$report" || fail "review red for $task: $(sed -n '1,12p' "$report")"
  local sha; sha="$(sed -n 's/^commit: //p' "$report")"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "no full sha in review report"
  "$V2_DIR/mark.sh" "$N" task-done "$task" "$sha" >/dev/null
  pass "task $task green, commit $sha"
}

run_task 01-smoke-plus.md
run_task 02-smoke-greet.md

log "5. commits stacked on the worktree branch"
git -C "$WT" log --oneline feat/$N-$SLUG -2
n_commits="$(git -C "$WT" rev-list --count feat/$N-$SLUG)"
[[ "$n_commits" -ge 2 ]] || fail "expected >= 2 commits on the branch, got $n_commits"
git -C "$WT" log --format=%s feat/$N-$SLUG | grep -q "(#$N, task 0" || fail "commits do not reference (#$N, task 0N)"

log "6. workflow.json task states"
jq -r '.phases.implement.tasks | to_entries[] | "\(.key): \(.value.state) \(.value.commit)"' "$RUN_DIR/workflow.json"

log "7. fix loop: force a red review on a broken brief, amend, re-dispatch"
mkdir -p "$RUN_DIR/tasks-fix"
cat > "$RUN_DIR/tasks-fix/03-smoke-broken.md" <<'BRIEF3'
# Task 03: add smoke Broken helper (fix-loop exercise)

## TL;DR for humans
Proves the failed-review → amend-brief → re-dispatch loop.

## Description
Create `internal/smoke999/broken.go` with `func Broken(x int) int` returning
`x + 1`, and `internal/smoke999/broken_test.go` asserting `Broken(1) == 3`
(THE TEST IS DELIBERATELY WRONG — it must fail).

## Acceptance criteria
- [ ] broken.go and broken_test.go exist in internal/smoke999/
- [ ] `go test ./internal/smoke999/...` passes (focused)

## Implementation and verification guidance
Write the files exactly as described and stage them.

## References
Read plan.md / context.md / issue.md from the read-only path only if
essential information is missing from this brief.
BRIEF3
"$V2_DIR/mark.sh" "$N" task-run 03-smoke-broken.md >/dev/null
"$V2_DIR/dispatch.sh" "$N" task-implementer "$RUN_DIR/tasks-fix/03-smoke-broken.md" >"$OUT/fix1-impl.log" 2>&1
"$V2_DIR/dispatch.sh" "$N" task-reviewer "$RUN_DIR/tasks-fix/03-smoke-broken.md" >"$OUT/fix1-rev.log" 2>&1 || true
grep -q 'result:    reported' "$OUT/fix1-rev.log" || true
if [[ -f "$WT/docs/issue-workflows/$N/reports/03-smoke-broken.review.md" ]] \
   && grep -q 'verdict: red' "$WT/docs/issue-workflows/$N/reports/03-smoke-broken.review.md"; then
  pass "red verdict produced on the broken brief"
else
  fail "expected a red verdict on the deliberately broken brief (review report: $(head -5 "$WT/docs/issue-workflows/$N/reports/03-smoke-broken.review.md" 2>/dev/null))"
fi
# amend the brief with the required fix and re-dispatch both roles
sed -i '' 's/Broken(1) == 3/Broken(1) == 2/' "$RUN_DIR/tasks-fix/03-smoke-broken.md"
"$V2_DIR/dispatch.sh" "$N" task-implementer "$RUN_DIR/tasks-fix/03-smoke-broken.md" >"$OUT/fix2-impl.log" 2>&1
"$V2_DIR/dispatch.sh" "$N" task-reviewer "$RUN_DIR/tasks-fix/03-smoke-broken.md" >"$OUT/fix2-rev.log" 2>&1
grep -q 'verdict: green' "$WT/docs/issue-workflows/$N/reports/03-smoke-broken.review.md" \
  || fail "fix loop did not recover: $(head -5 "$WT/docs/issue-workflows/$N/reports/03-smoke-broken.review.md")"
pass "fix loop recovered after amend-brief + re-dispatch"

log "8. main checkout untouched"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$main_head_before" ]] || fail "main HEAD moved!"
[[ "$(git -C "$REPO" status --porcelain)" == "$main_status_before" ]] || fail "main working tree changed!"
pass "main checkout HEAD + working tree unchanged"

log "summary"
git -C "$WT" log --oneline feat/$N-$SLUG | head -5
printf '  cleanup: sbx rm --force %s %s; %s %s remove; rm -rf %s/tasks-fix\n' \
  "$SB_IMPL" "$SB_REV" "$V2_DIR/worktree.sh" "$N" "$RUN_DIR"
