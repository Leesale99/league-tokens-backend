#!/usr/bin/env bash
# Phase A: Verifies whether PR changes meet the requirements from its
# linked issue. Outputs a checklist and discovery flags via GITHUB_OUTPUT.
# Does NOT touch PR body or labels.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ── Find linked issue from PR body ─────────────────────────────────────

CURRENT_BODY=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
ISSUE_NUM=$(echo "$CURRENT_BODY" | grep -oiP '(?:close|closes|fix|fixes|resolve|resolves)\s*:?\s*#\K\d+' | head -1 || true)

if [ -z "$ISSUE_NUM" ]; then
  echo "No linked issue found."
  echo "no-issue=true" >> "$GITHUB_OUTPUT"
  echo "issue-num=" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Linked issue: #$ISSUE_NUM"
echo "no-issue=false" >> "$GITHUB_OUTPUT"
echo "issue-num=$ISSUE_NUM" >> "$GITHUB_OUTPUT"

# ── Check if all requirements already met (token-saving skip) ──────────

if echo "$CURRENT_BODY" | grep -q '<!-- requirements-review-start -->'; then
  SECTION=$(echo "$CURRENT_BODY" | sed -n '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/p')
  TOTAL=$(echo "$SECTION" | grep -F -c '[' 2>/dev/null || true)
  UNCHECKED=$(echo "$SECTION" | grep -F -c '[ ]' 2>/dev/null || true)
  if [ "${TOTAL:-0}" -gt 0 ] && [ "${UNCHECKED:-0}" -eq 0 ]; then
    echo "All requirements already satisfied — skipping re-verification."
    {
      echo "checklist<<CHECKLIST_EOF"
      printf '%s\n' "$SECTION"
      echo "CHECKLIST_EOF"
    } >> "$GITHUB_OUTPUT"
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

# ── Output checklist section (including markers) to GITHUB_OUTPUT ──────

{
  echo "checklist<<CHECKLIST_EOF"
  echo "<!-- requirements-review-start -->"
  echo ""
  echo "## Requirements Verification — Issue #$ISSUE_NUM"
  echo ""
  printf '%s\n' "$CONTENT"
  echo ""
  echo "---"
  echo ""
  echo "<!-- requirements-review-end -->"
  echo "CHECKLIST_EOF"
} >> "$GITHUB_OUTPUT"
