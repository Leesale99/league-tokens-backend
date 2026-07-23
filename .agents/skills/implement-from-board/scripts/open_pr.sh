#!/usr/bin/env bash
set -euo pipefail

# Open a PR from the worktree branch.
# Usage: open_pr.sh <worktree_path> <issue_number> <title> <body>
# Output: JSON with {pr_url}

WORKTREE_PATH="$1"
ISSUE_NUM="$2"
TITLE="$3"
BODY="$4"

cd "$WORKTREE_PATH"

# Check if there are uncommitted changes
if ! git diff --quiet --cached 2>/dev/null || ! git diff --quiet 2>/dev/null; then
  git add -A
  git commit -m "$TITLE (closes #$ISSUE_NUM)" 2>/dev/null
fi

BRANCH=$(git branch --show-current)
git push -u origin "$BRANCH" 2>/dev/null

PR_URL=$(gh pr create \
  --title "$TITLE" \
  --body-file - 2>/dev/null <<EOF
Closes #$ISSUE_NUM

$BODY
EOF
)

echo "{\"pr_url\": \"$PR_URL\"}"
