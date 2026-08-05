#!/usr/bin/env bash
set -euo pipefail

# Usage: create_branch.sh <issue-number> <issue-title>
# Creates feat/<issue>-<slug> from origin/main. Refuses a dirty checkout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
issue_number="${1:?issue number is required}"
title="${2:?issue title is required}"
base="$(jq -r '.branch.base' "$CONFIG")"
prefix="$(jq -r '.branch.prefix' "$CONFIG")"

# Step 4 snapshots the issue before this script runs. Permit that one expected
# untracked file, but reject every other local change so a new branch never
# captures unrelated work.
allowed_snapshot="?? docs/issue-workflows/$issue_number/issue.md"
unexpected_changes="$(git status --porcelain --untracked-files=all | grep -Fvx "$allowed_snapshot" || true)"
if [[ -n "$unexpected_changes" ]]; then
  echo 'Checkout has changes other than the new issue snapshot; commit, stash, or discard them before creating an issue branch.' >&2
  exit 1
fi

git fetch origin "$base"
slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
slug="${slug:0:40}"
if [[ -z "$slug" ]]; then
  slug="issue"
fi
branch="$prefix/$issue_number-$slug"

if git show-ref --verify --quiet "refs/heads/$branch" || git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  printf 'Branch already exists: %s\n' "$branch" >&2
  exit 1
fi

git switch --create "$branch" "origin/$base" >&2
jq -n --arg branch "$branch" --arg base "origin/$base" '{branch: $branch, base: $base}'
