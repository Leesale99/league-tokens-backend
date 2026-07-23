#!/usr/bin/env bash
set -euo pipefail

# Create a git worktree and branch for an issue.
# Usage: create_worktree.sh <issue_number> <title_slug>
# Output: JSON with {worktree_path, branch_name}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(dirname "$SCRIPT_DIR")/config.json"
PREFIX=$(jq -r '.worktree.prefix' "$CONFIG")
BRANCH_PREFIX=$(jq -r '.worktree.branch_prefix' "$CONFIG")
PARENT_DIR=$(jq -r '.worktree.parent_dir' "$CONFIG")

ISSUE_NUM="$1"
SLUG="$2"

BRANCH_NAME="${BRANCH_PREFIX}/${ISSUE_NUM}-${SLUG}"
WORKTREE_PATH="${PARENT_DIR}/${PREFIX}-${ISSUE_NUM}"

if [ -d "$WORKTREE_PATH" ]; then
  echo "{\"error\": \"Worktree already exists at $WORKTREE_PATH\"}" >&2
  exit 1
fi

git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" 2>/dev/null

echo "{\"worktree_path\": \"$WORKTREE_PATH\", \"branch_name\": \"$BRANCH_NAME\"}"
