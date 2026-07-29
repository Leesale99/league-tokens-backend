#!/usr/bin/env bash
# Aggregates PR review comments from the four focus jobs into the PR
# description body between <!-- review-summary-start --> and
# <!-- review-summary-end --> markers.
# Reads inline comments posted via create_pull_request_review — no JSON artifacts.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

comments_raw="$tmp/comments.jsonl"

gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq '
  .[]
  | select(.user.login == "github-actions[bot]")
  | select(.body | test("\\*\\*(blocking|important|suggestion)\\*\\*"))
  | {body: .body, path: .path, line: .line}
' > "$comments_raw"

# ── Parse each comment ─────────────────────────────────────────────────

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

# ── Deduplicate by path+line, keep highest severity ────────────────────

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
