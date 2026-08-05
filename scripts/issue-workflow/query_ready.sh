#!/usr/bin/env bash
set -euo pipefail

# Usage: query_ready.sh [issue-number]
# Prints {number, title, item_id}. Without an argument, selects the first Ready item.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
OWNER="$(jq -r '.project.owner' "$CONFIG")"
PROJECT_NUM="$(jq -r '.project.number' "$CONFIG")"

if [[ -n "${1:-}" ]]; then
  issue_number="$1"
  item_id="$(gh api graphql -f query="
{
  user(login: \"$OWNER\") {
    projectV2(number: $PROJECT_NUM) {
      items(first: 100) {
        nodes { id content { ... on Issue { number } } }
      }
    }
  }
}" --jq ".data.user.projectV2.items.nodes[] | select(.content.number == $issue_number) | .id")"

  if [[ -z "$item_id" ]]; then
    printf 'Issue #%s is not on this project board.\n' "$issue_number" >&2
    exit 1
  fi

  title="$(gh issue view "$issue_number" --json title --jq '.title')"
  jq -n --argjson number "$issue_number" --arg title "$title" --arg item_id "$item_id" \
    '{number: $number, title: $title, item_id: $item_id}'
  exit 0
fi

result="$(gh api graphql -f query="
{
  user(login: \"$OWNER\") {
    projectV2(number: $PROJECT_NUM) {
      items(first: 100) {
        nodes {
          id
          content { ... on Issue { number title } }
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2SingleSelectField { name } }
              }
            }
          }
        }
      }
    }
  }
}")"

ready_item="$(jq -c '
  [.data.user.projectV2.items.nodes[]
   | select(.content.number != null)
   | select(any(.fieldValues.nodes[]?; .field.name == "Status" and .name == "Ready"))
   | {number: .content.number, title: .content.title, item_id: .id}]
  | first // empty
' <<<"$result")"

if [[ -z "$ready_item" ]]; then
  echo 'No tasks are in the Ready column.' >&2
  exit 1
fi

printf '%s\n' "$ready_item"
