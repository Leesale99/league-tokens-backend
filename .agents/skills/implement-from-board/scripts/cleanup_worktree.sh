#!/usr/bin/env bash
set -euo pipefail

# Remove a git worktree.
# Usage: cleanup_worktree.sh <issue_number>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(dirname "$SCRIPT_DIR")/config.json"
PREFIX=$(jq -r '.worktree.prefix' "$CONFIG")
PARENT_DIR=$(jq -r '.worktree.parent_dir' "$CONFIG")

ISSUE_NUM="$1"
WORKTREE_PATH="${PARENT_DIR}/${PREFIX}-${ISSUE_NUM}"

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "{\"cleaned\": false, \"reason\": \"worktree not found\"}"
  exit 0
fi

git worktree remove "$WORKTREE_PATH" 2>/dev/null
echo "{\"cleaned\": true, \"worktree_path\": \"$WORKTREE_PATH\"}"
