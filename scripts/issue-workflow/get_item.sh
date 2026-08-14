#!/usr/bin/env bash
set -euo pipefail

# Usage: get_item.sh [--expect <status>] <issue-number>
# Prints {number, title, item_id, status} for an issue on the project board,
# regardless of board status. With --expect, exits 1 unless the item's status
# matches. Status values are the GitHub display names ("Backlog", "Ready",
# "In progress", "In review", "Done").

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
OWNER="$(jq -r '.project.owner' "$CONFIG")"
PROJECT_NUM="$(jq -r '.project.number' "$CONFIG")"

expect=""
if [[ "${1:-}" == "--expect" ]]; then
  expect="${2:-}"
  if [[ -z "$expect" ]]; then
    printf 'Usage: get_item.sh [--expect <status>] <issue-number>\n' >&2
    exit 1
  fi
  shift 2
fi

issue_number="${1:-}"
if [[ -z "$issue_number" ]]; then
  printf 'Usage: get_item.sh [--expect <status>] <issue-number>\n' >&2
  exit 1
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

item="$(jq -c --argjson number "$issue_number" '
  [.data.user.projectV2.items.nodes[]
   | select(.content.number == $number)
   | {number: .content.number,
      title: .content.title,
      item_id: .id,
      status: ([.fieldValues.nodes[]? | select(.field.name == "Status") | .name] | first // "")}]
  | first // empty
' <<<"$result")"

if [[ -z "$item" ]]; then
  printf 'Issue #%s is not on this project board.\n' "$issue_number" >&2
  exit 1
fi

status="$(jq -r '.status' <<<"$item")"
if [[ -n "$expect" && "$status" != "$expect" ]]; then
  printf 'Issue #%s is %s, expected %s.\n' "$issue_number" "${status:-unset}" "$expect" >&2
  exit 1
fi

printf '%s\n' "$item"
