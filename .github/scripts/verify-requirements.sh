#!/usr/bin/env bash
# Verifies whether PR changes meet the requirements from its linked issue.
# Injects a checklist into the PR body under <!-- requirements-review-start -->
# and <!-- requirements-review-end --> markers.
# Manages the `no-requirements` label (set when no linked issue found)
# and the `requirements-verified` label (set when all checkboxes ticked).
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ── Find linked issue from PR body ─────────────────────────────────────

CURRENT_BODY=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
ISSUE_NUM=$(echo "$CURRENT_BODY" | grep -oiP '(?:close|closes|fix|fixes|resolve|resolves)\s*:?\s*#\K\d+' | head -1 || true)

if [ -z "$ISSUE_NUM" ]; then
  echo "No linked issue found — adding no-requirements, removing stale requirements-verified."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label no-requirements 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
  exit 0
fi

echo "Linked issue: #$ISSUE_NUM"

# ── Remove no-requirements (there are now requirements to verify) ──────

gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label no-requirements 2>/dev/null || true

# ── Check if all requirements already met (token-saving skip) ──────────

if echo "$CURRENT_BODY" | grep -q '<!-- requirements-review-start -->'; then
  SECTION=$(echo "$CURRENT_BODY" | sed -n '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/p')
  TOTAL=$(echo "$SECTION" | grep -F -c '[' 2>/dev/null || true)
  UNCHECKED=$(echo "$SECTION" | grep -F -c '[ ]' 2>/dev/null || true)
  if [ "${TOTAL:-0}" -gt 0 ] && [ "${UNCHECKED:-0}" -eq 0 ]; then
    echo "All requirements already satisfied — skipping re-verification."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-verified 2>/dev/null || true
    exit 0
  fi
  echo "$UNCHECKED requirement(s) still not met — re-verifying."
fi

# ── Fetch issue ────────────────────────────────────────────────────────

ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json body,title)
ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_DATA" | jq -r '.body')

echo "Fetched issue: $ISSUE_TITLE"

# ── Get PR diff ────────────────────────────────────────────────────────

DIFF=$(gh pr diff "$PR_NUMBER" --repo "$REPO" 2>/dev/null | head -n 800 || true)

# ── Build prompt ───────────────────────────────────────────────────────

cat ".github/prompts/requirements-verification.md" > "$tmp/prompt.txt"
printf "\n## Issue\n" >> "$tmp/prompt.txt"
printf "**Title:** %s\n\n" "$ISSUE_TITLE" >> "$tmp/prompt.txt"
printf "%s\n" "$ISSUE_BODY" >> "$tmp/prompt.txt"
printf "\n## PR Diff\n\`\`\`diff\n%s\n\`\`\`\n" "$DIFF" >> "$tmp/prompt.txt"

# ── Call AI API ────────────────────────────────────────────────────────

SYSTEM_PROMPT="You are a requirements verifier analyzing whether PR changes satisfy issue requirements. Output ONLY the requested markdown format."

echo "Calling AI API ..."
RESPONSE=$(curl -s "https://opencode.ai/zen/go/v1/chat/completions" \
  -H "Authorization: Bearer $OPENCODE_GO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "deepseek-v4-flash" \
    --arg system "$SYSTEM_PROMPT" \
    --rawfile prompt "$tmp/prompt.txt" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $prompt}
      ]
    }')"
)

CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

if [ -z "$CONTENT" ]; then
  echo "::warning::AI returned empty or invalid response — skipping."
  echo "Raw response:"
  echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
  exit 0
fi

echo "AI analysis received (${#CONTENT} chars)."

# ── Build PR body section ──────────────────────────────────────────────

{
  echo "<!-- requirements-review-start -->"
  echo ""
  echo "## Requirements Verification — Issue #$ISSUE_NUM"
  echo ""
  printf '%s\n' "$CONTENT"
  echo ""
  echo "---"
  echo ""
  echo "<!-- requirements-review-end -->"
} > "$tmp/section.txt"

SECTION=$(cat "$tmp/section.txt")

# ── Inject into PR body ────────────────────────────────────────────────

if echo "$CURRENT_BODY" | grep -q '<!-- requirements-review-start -->'; then
  CLEAN_BODY=$(echo "$CURRENT_BODY" | sed '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/d')
else
  CLEAN_BODY="$CURRENT_BODY"
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" --body "${CLEAN_BODY}"$'\n\n'"${SECTION}"

echo "Requirements verification section written to PR body."

# ── Apply requirements-verified label ──────────────────────────────────

printf '%s\n' "$CONTENT" > "$tmp/content.txt"
UNCHECKED=$(grep -F -c '[ ]' "$tmp/content.txt" || true)

if [ "$UNCHECKED" -eq 0 ]; then
  echo "All requirements met — adding requirements-verified label."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-verified 2>/dev/null || true
else
  echo "$UNCHECKED requirement(s) not met — removing requirements-verified label."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
fi
