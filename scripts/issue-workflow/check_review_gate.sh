#!/usr/bin/env bash
set -euo pipefail

# Usage: check_review_gate.sh <issue-number>
# Machine-checkable gate for the /issue-open-pr step. Exits 0 only when
# docs/issue-workflows/<issue>/reviews/summary.md carries green frontmatter:
# status: green, blocking_unresolved: 0, reviewed_head matching the current
# HEAD. Exits 1 otherwise, with the reason on stderr — no LLM judgement.

issue_number="${1:?issue number is required}"
issue_dir="docs/issue-workflows/$issue_number"
summary="$issue_dir/reviews/summary.md"

fail() { printf 'Review gate: %s\n' "$*" >&2; exit 1; }

[[ -f "$summary" ]] || fail "$summary is missing — final review has not produced a summary."

# Extract the leading frontmatter block (--- ... --- at the top of the file).
meta="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$summary")"
[[ -n "$meta" ]] || fail "$summary has no frontmatter block."

status="$(printf '%s\n' "$meta" | sed -n 's/^status:[[:space:]]*//p' | head -1)"
[[ "$status" == "green" || "$status" == "red" ]] \
  || fail "$summary frontmatter status is '${status:-missing}', expected green|red."

blocking="$(printf '%s\n' "$meta" | sed -n 's/^blocking_unresolved:[[:space:]]*//p' | head -1)"
[[ "$blocking" =~ ^[0-9]+$ ]] \
  || fail "$summary frontmatter blocking_unresolved is '${blocking:-missing}', expected a non-negative integer."

if [[ "$status" == "red" || "$blocking" != "0" ]]; then
  fail "$summary is red ($blocking unresolved blocking finding(s))."
fi

reviewed_head="$(printf '%s\n' "$meta" | sed -n 's/^reviewed_head:[[:space:]]*//p' | head -1)"
[[ "$reviewed_head" =~ ^[0-9a-f]{7,40}$ ]] \
  || fail "$summary frontmatter reviewed_head is '${reviewed_head:-missing}', expected a commit sha."

head_sha="$(git rev-parse HEAD)"
if [[ "$head_sha" != "$reviewed_head"* ]]; then
  fail "$summary was reviewed at $reviewed_head but HEAD is $head_sha — re-review the new commits first."
fi

printf 'Review gate green: %s (status: %s, blocking_unresolved: %s, reviewed_head: %s).\n' \
  "$summary" "$status" "$blocking" "$reviewed_head"
