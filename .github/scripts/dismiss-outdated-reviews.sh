#!/usr/bin/env bash
# Dismisses outdated bot comments on PRs after new commits.
# A comment is outdated when its file+line was modified in the latest diff.
# Outputs existing_comments (JSON array of {path, line}) for the review
# agent to skip when re-reviewing.
set -euo pipefail

PR_NUMBER="$1"
REPO="$2"
BASE_BRANCH="${3:-main}"

# Fetch all bot comments
comments=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate \
  --jq 'map(select(.user.login | endswith("[bot]") and .line != null))')

count=$(echo "$comments" | jq 'length')
if [ "$count" -eq 0 ]; then
  echo "existing_comments=[]" >>"$GITHUB_OUTPUT"
  echo "dismissed=0" >>"$GITHUB_OUTPUT"
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
  remaining=$(echo "$remaining" | jq --arg path "$path" --argjson line "$line" '. + [{"path": $path, "line": $line}]')
done < <(echo "$comments" | jq -c '.[]')

echo "existing_comments=$remaining" >>"$GITHUB_OUTPUT"
echo "dismissed=$dismissed" >>"$GITHUB_OUTPUT"
