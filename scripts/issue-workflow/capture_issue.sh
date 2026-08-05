#!/usr/bin/env bash
set -euo pipefail

# Usage: capture_issue.sh <issue-number> <board-item-id>
# Writes the issue snapshot used by later workflow phases.

issue_number="${1:?issue number is required}"
board_item_id="${2:?board item id is required}"
issue_dir="docs/issue-workflows/$issue_number"
issue_file="$issue_dir/issue.md"

if [[ -e "$issue_file" ]]; then
  printf 'Refusing to overwrite %s\n' "$issue_file" >&2
  exit 1
fi

mkdir -p "$issue_dir"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
gh issue view "$issue_number" --json number,title,body,labels,comments,url,author,createdAt,updatedAt >"$tmp"

{
  printf '%s\n' '---'
  jq -r --arg board_item_id "$board_item_id" '
    "issue: \(.number)",
    "board_item_id: \($board_item_id)",
    "url: \(.url)",
    "author: \(.author.login)",
    "created_at: \(.createdAt)",
    "updated_at: \(.updatedAt)"' "$tmp"
  printf '%s\n\n' '---'
  jq -r '"# Issue #\(.number): \(.title)"' "$tmp"
  printf '\n## Labels\n\n'
  jq -r 'if (.labels | length) == 0 then "_None_" else .labels[].name end' "$tmp"
  printf '\n## Description\n\n'
  jq -r 'if .body == "" then "_No description provided._" else .body end' "$tmp"
  printf '\n## Comments\n'
  jq -r '
    if (.comments | length) == 0 then "\n_None_"
    else .comments[] | "\n### @\(.author.login) — \(.createdAt)\n\n\(.body)"
    end' "$tmp"
} >"$issue_file"

printf '%s\n' "$issue_file"
