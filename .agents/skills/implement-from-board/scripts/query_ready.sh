#!/usr/bin/env bash
set -euo pipefail

# Get the first item in the "Ready" column from the project board.
# Usage: query_ready.sh [issue_number]
# If issue_number is provided, fetches that specific issue instead.
# Output: JSON with {number, title, item_id}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(dirname "$SCRIPT_DIR")/config.json"
OWNER=$(jq -r '.project.owner' "$CONFIG")
PROJECT_NUM=$(jq -r '.project.number' "$CONFIG")

if [ "${1:-}" != "" ]; then
  ISSUE_NUM="$1"
  # Fetch specific issue and verify it exists on the project
  ITEM_ID=$(gh api graphql -f query="
{
  user(login: \"$OWNER\") {
    projectV2(number: $PROJECT_NUM) {
      items(first: 50) {
        nodes {
          id
          content { ... on Issue { number title } }
        }
      }
    }
  }
}" --jq ".data.user.projectV2.items.nodes[] | select(.content.number == $ISSUE_NUM) | .id" 2>/dev/null)

  if [ -z "$ITEM_ID" ]; then
    echo "{\"error\": \"Issue #$ISSUE_NUM not found on project board\"}" >&2
    exit 1
  fi

  TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>/dev/null)
  echo "{\"number\": $ISSUE_NUM, \"title\": \"$TITLE\", \"item_id\": \"$ITEM_ID\"}"
  exit 0
fi

# Query for first Ready item
RESULT=$(gh api graphql -f query="
{
  user(login: \"$OWNER\") {
    projectV2(number: $PROJECT_NUM) {
      items(first: 50) {
        nodes {
          id
          content { ... on Issue { number title } }
          fieldValues(first: 10) {
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
}" 2>/dev/null)

# Find first Ready item
READY_ITEM=$(echo "$RESULT" | jq -r '
  [.data.user.projectV2.items.nodes[] |
   select(.fieldValues.nodes[] | select(.field.name == "Status" and .name == "Ready")) |
   {number: .content.number, title: .content.title, item_id: .id}] | first // empty
')

if [ -z "$READY_ITEM" ]; then
  echo '{"error": "No tasks in Ready column"}' >&2
  exit 1
fi

echo "$READY_ITEM"
