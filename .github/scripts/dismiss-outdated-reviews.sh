#!/usr/bin/env bash
# Dismisses outdated bot comments on PRs after new commits.
# A comment is outdated when its file+line was modified in the latest diff.
# Outputs existing_comments (JSON array of {path, line}) for the review
# agent to skip when re-reviewing. Also prints a human-readable summary to
# the job log and emits focus stats (found/dismissed/remaining + per-file
# focus) so the report-and-gate job can render run-specific metadata.
set -euo pipefail

PR_NUMBER="$1"
REPO="$2"
BASE_BRANCH="${3:-main}"

# Fetch all bot comments
comments=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate \
  --jq 'map(select((.user.login | endswith("[bot]")) and .line != null))')

count=$(echo "$comments" | jq 'length')
echo "PR #$PR_NUMBER: found $count bot comment(s) from previous rounds."
echo "found=$count" >>"$GITHUB_OUTPUT"
if [ "$count" -eq 0 ]; then
  echo "PR #$PR_NUMBER: nothing to dismiss."
  echo "existing_comments=[]" >>"$GITHUB_OUTPUT"
  echo "dismissed=0" >>"$GITHUB_OUTPUT"
  echo "remaining=0" >>"$GITHUB_OUTPUT"
  echo "focus=[]" >>"$GITHUB_OUTPUT"
  exit 0
fi

# Get files changed in the latest diff
CHANGED=$(git diff "origin/$BASE_BRANCH..HEAD" --name-only)

dismissed=0
remaining="[]"

while read -r comment; do
  [ -z "$comment" ] && continue
  path=$(echo "$comment" | jq -r '.path // empty')
  line=$(echo "$comment" | jq -r '.line // empty')
  id=$(echo "$comment" | jq -r '.id')
  [ -z "$path" ] && continue

  if [ -n "$line" ] && echo "$CHANGED" | grep -Fxq "$path"; then
    # File was modified — check if the specific line changed
    if git diff "origin/$BASE_BRANCH..HEAD" -- "$path" 2>/dev/null |
      grep -q "\+\b$line\b"; then
      gh api "repos/$REPO/pulls/comments/$id" -X DELETE 2>/dev/null || true
      dismissed=$((dismissed + 1))
      continue
    fi
  fi

  # Comment is still relevant
  remaining=$(echo "$remaining" | jq -c --arg path "$path" --argjson line "$line" '. + [{"path": $path, "line": $line}]')
done < <(echo "$comments" | jq -c '.[]')

remaining_count=$(echo "$remaining" | jq 'length')

# Per-file focus breakdown (JSON, most comments first) for the PR body.
focus=$(echo "$remaining" | jq -c 'group_by(.path) | map({path: .[0].path, count: length}) | sort_by(.count) | reverse')

echo "PR #$PR_NUMBER: dismissed $dismissed outdated comment(s) (file+line changed) — skipped this round."
echo "PR #$PR_NUMBER: kept $remaining_count comment(s) still relevant — this round's review is focused on them."
if [ "$remaining_count" -gt 0 ]; then
  echo "PR #$PR_NUMBER: focus breakdown (kept comments per file):"
  echo "$focus" | jq -r '.[] | "  \(.count)x \(.path)"'
fi

echo 'existing_comments<<EOF' >>"$GITHUB_OUTPUT"
echo "$remaining" >>"$GITHUB_OUTPUT"
echo 'EOF' >>"$GITHUB_OUTPUT"
echo "dismissed=$dismissed" >>"$GITHUB_OUTPUT"
echo "remaining=$remaining_count" >>"$GITHUB_OUTPUT"
echo 'focus<<EOF' >>"$GITHUB_OUTPUT"
echo "$focus" >>"$GITHUB_OUTPUT"
echo 'EOF' >>"$GITHUB_OUTPUT"
