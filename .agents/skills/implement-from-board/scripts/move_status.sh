#!/usr/bin/env bash
set -euo pipefail

# Move a project board item to a different status column.
# Usage: move_status.sh <item_id> <status_name>
# status_name: backlog | ready | in_progress | in_review | done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(dirname "$SCRIPT_DIR")/config.json"
PROJECT_ID=$(jq -r '.project.node_id' "$CONFIG")
STATUS_FIELD=$(jq -r '.fields.status.field_id' "$CONFIG")

ITEM_ID="$1"
STATUS_NAME="$2"

OPTION_ID=$(jq -r ".fields.status.options.$STATUS_NAME" "$CONFIG")

if [ "$OPTION_ID" = "null" ]; then
  echo "{\"error\": \"Unknown status: $STATUS_NAME\"}" >&2
  exit 1
fi

gh project item-edit \
  --project-id "$PROJECT_ID" \
  --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD" \
  --single-select-option-id "$OPTION_ID" 2>/dev/null

echo "{\"moved_to\": \"$STATUS_NAME\", \"item_id\": \"$ITEM_ID\"}"
