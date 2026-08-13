#!/usr/bin/env bash
set -euo pipefail

# Usage: pick_ready.sh
# Prints {number, title, item_id, status} for the first Ready item on the
# board. Exits 1 when no item is Ready. Never falls back to Backlog.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
OWNER="$(jq -r '.project.owner' "$CONFIG")"
PROJECT_NUM="$(jq -r '.project.number' "$CONFIG")"

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
   | {number: .content.number,
      title: .content.title,
      item_id: .id,
      status: "Ready"}]
  | first // empty
' <<<"$result")"

if [[ -z "$ready_item" ]]; then
  echo 'No tasks are in the Ready column.' >&2
  exit 1
fi

printf '%s\n' "$ready_item"
