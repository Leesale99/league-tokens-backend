#!/usr/bin/env bash
# Aggregates review summaries from parallel review matrix jobs into the
# PR description body between <!-- review-summary-start --> and
# <!-- review-summary-end --> markers.
# Each focus job outputs a fenced JSON array; this script merges,
# deduplicates, and builds the PR body.
set -euo pipefail

FOCI=("quality" "correctness" "security" "quality-depth")

# ── Extract JSON array from summary file ──────────────────────────────

extract_json() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo '[]'
    return
  fi

  local content json
  content=$(cat "$file")

  # Try JSON code fence first
  json=$(echo "$content" | sed -n '/^```json$/,/^```$/p' | sed '1d;$d' | grep -v '^```' || true)

  # Fallback: strip everything outside the outermost [ ] pair
  if [ -z "${json:-}" ]; then
    json=$(echo "$content" | tr -d '\n' | sed 's/.*\(\[.*\]\).*/\1/' || true)
  fi

  if [ -z "${json:-}" ]; then
    json="$content"
  fi

  # Validate it's an array; fall back to empty on failure
  if echo "$json" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo "$json"
  else
    echo '[]'
  fi
}

# ── Collect and merge all findings ────────────────────────────────────

all_findings='[]'
total_blocking=0
total_important=0
total_suggestion=0

for focus in "${FOCI[@]}"; do
  sf="summaries/${focus}-summary/${focus}-review-summary.json"
  findings=$(extract_json "$sf")

  # Validate each entry has required fields
  findings=$(echo "$findings" | jq -c '[.[] | select(
    .severity and .path and .line and .description and
    (.severity == "blocking" or .severity == "important" or .severity == "suggestion")
  )]' 2>/dev/null || echo '[]')

  b=$(echo "$findings" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo 0)
  i=$(echo "$findings" | jq '[.[] | select(.severity == "important")] | length' 2>/dev/null || echo 0)
  s=$(echo "$findings" | jq '[.[] | select(.severity == "suggestion")] | length' 2>/dev/null || echo 0)

  total_blocking=$((total_blocking + b))
  total_important=$((total_important + i))
  total_suggestion=$((total_suggestion + s))

  all_findings=$(echo "$all_findings" "$findings" | jq -sc 'add' 2>/dev/null || echo '[]')
done

# ── Deduplicate by path+line, keeping highest severity ────────────────
# Counts below are recomputed from deduplicated results so the summary
# line matches the listed items.

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

# ── Build PR body ─────────────────────────────────────────────────────

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
  blocking_items=$(echo "$all_findings" | jq -r '
    [.[] | select(.severity == "blocking")] |
    .[] | "- [ ] `\(.path):\(.line)` — \(.description)"
  ' 2>/dev/null || true)

  important_items=$(echo "$all_findings" | jq -r '
    [.[] | select(.severity == "important")] |
    .[] | "- [ ] `\(.path):\(.line)` — \(.description)"
  ' 2>/dev/null || true)

  suggestion_items=$(echo "$all_findings" | jq -r '
    [.[] | select(.severity == "suggestion")] |
    .[] | "- [ ] `\(.path):\(.line)` — \(.description)"
  ' 2>/dev/null || true)

  if [ -n "${blocking_items:-}" ]; then
    out+=("### 🔴 Blocking")
    out+=("")
    while IFS= read -r l; do out+=("$l"); done <<< "$blocking_items"
    out+=("")
  fi

  if [ -n "${important_items:-}" ]; then
    out+=("### 🟠 Important")
    out+=("")
    while IFS= read -r l; do out+=("$l"); done <<< "$important_items"
    out+=("")
  fi

  if [ -n "${suggestion_items:-}" ]; then
    out+=("### 🟡 Suggestion")
    out+=("")
    while IFS= read -r l; do out+=("$l"); done <<< "$suggestion_items"
    out+=("")
  fi
fi

out+=("---")
out+=("[View workflow →](https://github.com/$REPO/actions/runs/$RUN_ID)")
out+=("")
out+=("<!-- review-summary-end -->")

build=$(printf '%s\n' "${out[@]}")

# ── Inject into PR body ──────────────────────────────────────────────

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')

if echo "$current_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$current_body" | \
    sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
else
  clean_body="$current_body"
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" \
  --body "${clean_body}"$'\n\n'"${build}"
