#!/usr/bin/env bash
# Phase B+C: Aggregates review comments and requirements checklist into
# a combined report, publishes to PR body, manages all labels, and runs
# the merge gate check. Runs as the sink job after all Phase A jobs.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HAS_GO="${HAS_GO:-false}"
NO_ISSUE="${NO_ISSUE:-false}"

# ═══════════════════════════════════════════════════════════════════════
# Section B1 — Aggregate review comments (if Go files present)
# ═══════════════════════════════════════════════════════════════════════

total_blocking=0
review_section=""

if [ "$HAS_GO" = "true" ]; then
  echo "Aggregating review comments ..."

  comments_raw="$tmp/comments.jsonl"

  gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq '
    .[]
    | select(.user.login == "github-actions[bot]")
    | select(.body | test("\\*\\*(blocking|important|suggestion)\\*\\*"))
    | {body: .body, path: .path, line: .line}
  ' > "$comments_raw"

  all_findings='[]'

  while IFS= read -r raw; do
    body=$(echo "$raw" | jq -r '.body')
    path=$(echo "$raw" | jq -r '.path')
    line=$(echo "$raw" | jq -r '.line')

    first_line=$(echo "$body" | head -1)

    sev=$(echo "$first_line" | sed -n 's/^.*\*\*\(blocking\|important\|suggestion\)\*\*.*/\1/p')
    [ -z "${sev:-}" ] && continue

    title=$(echo "$first_line" | sed 's/^\*\*'"$sev"'\*\* — //;s/\*\*$//')

    desc=$(echo "$body" | sed '1,2d' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//' | head -c 200)

    if [ -n "$title" ] && [ -n "$desc" ]; then
      full_desc="$title. $desc"
    elif [ -n "$title" ]; then
      full_desc="$title"
    else
      full_desc="$desc"
    fi

    all_findings=$(echo "$all_findings" | jq -c \
      --arg sev "$sev" \
      --arg path "$path" \
      --argjson line "$line" \
      --arg desc "$full_desc" \
      '. + [{severity: $sev, path: $path, line: $line, description: $desc}]' \
      2>/dev/null || echo "$all_findings")

  done < "$comments_raw"

  all_findings=$(echo "$all_findings" | jq -c '
    group_by({path, line}) |
    map(
      sort_by(
        if .severity == "blocking" then 0
        elif .severity == "important" then 1
        else 2 end
      ) | .[0]
    )
  ' 2>/dev/null || echo '[]')

  total_blocking=$(echo "$all_findings" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo 0)
  total_important=$(echo "$all_findings" | jq '[.[] | select(.severity == "important")] | length' 2>/dev/null || echo 0)
  total_suggestion=$(echo "$all_findings" | jq '[.[] | select(.severity == "suggestion")] | length' 2>/dev/null || echo 0)

  out=()
  out+=("<!-- review-summary-start -->")
  out+=("")
  out+=("## AI Review Summary")
  out+=("")
  out+=("🔴 ${total_blocking} blocking · 🟠 ${total_important} important · 🟡 ${total_suggestion} suggestion")
  out+=("")

  if [ "$total_blocking" -eq 0 ] && [ "$total_important" -eq 0 ] && [ "$total_suggestion" -eq 0 ]; then
    out+=("No issues found.")
  else
    for sev_label in "blocking:### 🔴 Blocking" "important:### 🟠 Important" "suggestion:### 🟡 Suggestion"; do
      sev="${sev_label%%:*}"
      heading="${sev_label##*:}"
      items=$(echo "$all_findings" | jq -r \
        '[.[] | select(.severity == "'"$sev"'")] | .[] | "- [ ] `\(.path):\(.line)` — \(.description)"' \
        2>/dev/null || true)
      if [ -n "${items:-}" ]; then
        out+=("$heading")
        out+=("")
        while IFS= read -r l; do out+=("$l"); done <<< "$items"
        out+=("")
      fi
    done
  fi

  out+=("---")
  out+=("[View workflow →](https://github.com/$REPO/actions/runs/$RUN_ID)")
  out+=("")
  out+=("<!-- review-summary-end -->")

  review_section=$(printf '%s\n' "${out[@]}")
  echo "Review summary built (${total_blocking} blocking, ${total_important} important, ${total_suggestion} suggestion)."
else
  echo "No Go files changed — skipping review summary."
fi

# ═══════════════════════════════════════════════════════════════════════
# Section B2 — Build combined report
# ═══════════════════════════════════════════════════════════════════════

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
clean_body="$current_body"

if echo "$clean_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
fi

if echo "$clean_body" | grep -q '<!-- requirements-review-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/d')
fi

new_body="$clean_body"

if [ -n "$review_section" ]; then
  new_body="${new_body}"$'\n\n'"${review_section}"
fi

if [ "$NO_ISSUE" != "true" ] && [ -n "${CHECKLIST:-}" ]; then
  new_body="${new_body}"$'\n\n'"${CHECKLIST}"
fi

# ═══════════════════════════════════════════════════════════════════════
# Section C1 — Publish combined report to PR body
# ═══════════════════════════════════════════════════════════════════════

gh pr edit "$PR_NUMBER" --repo "$REPO" --body "$new_body"
echo "PR body updated."

# ═══════════════════════════════════════════════════════════════════════
# Section C2 — Set all labels
# ═══════════════════════════════════════════════════════════════════════

# Code review axis: no-review ↔ code-review-passed
if [ "$HAS_GO" != "true" ]; then
  echo "No Go files — applying no-review, removing code-review-passed."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label no-review 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label code-review-passed 2>/dev/null || true
else
  echo "Go files present — removing no-review."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label no-review 2>/dev/null || true
  if [ "$total_blocking" -eq 0 ]; then
    echo "No blocking issues — applying code-review-passed."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label code-review-passed 2>/dev/null || true
  else
    echo "$total_blocking blocking issue(s) — removing code-review-passed."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label code-review-passed 2>/dev/null || true
  fi
fi

# Requirements axis: no-requirements ↔ requirements-verified
if [ "$NO_ISSUE" = "true" ]; then
  echo "No linked issue — applying no-requirements, removing requirements-verified."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label no-requirements 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
else
  echo "Linked issue present — removing no-requirements."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label no-requirements 2>/dev/null || true

  if [ -n "${CHECKLIST:-}" ]; then
    printf '%s\n' "$CHECKLIST" > "$tmp/checklist.txt"
    UNCHECKED=$(grep -F -c '[ ]' "$tmp/checklist.txt" || true)
    if [ "${UNCHECKED:-0}" -eq 0 ]; then
      echo "All requirements met — applying requirements-verified."
      gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-verified 2>/dev/null || true
    else
      echo "$UNCHECKED requirement(s) not met — removing requirements-verified."
      gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
    fi
  else
    echo "No checklist content — removing requirements-verified."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Section C3 — Gate check
# ═══════════════════════════════════════════════════════════════════════

CI_RESULT="${CI_RESULT:-skipped}"
VERIFY_RESULT="${VERIFY_RESULT:-skipped}"

if [ "$CI_RESULT" != "success" ]; then
  echo "::error::CI did not pass ($CI_RESULT)"
  exit 1
fi

if [ "$VERIFY_RESULT" != "success" ]; then
  echo "::error::Requirements verification did not pass ($VERIFY_RESULT)"
  exit 1
fi

LABELS=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)

if ! echo "$LABELS" | grep -qE '^no-review$|^code-review-passed$'; then
  echo "::error::Missing no-review or code-review-passed label"
  exit 1
fi

if ! echo "$LABELS" | grep -qE '^no-requirements$|^requirements-verified$'; then
  echo "::error::Missing no-requirements or requirements-verified label"
  exit 1
fi

echo "::notice::All merge gates passed."
