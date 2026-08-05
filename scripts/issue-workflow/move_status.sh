#!/usr/bin/env bash
set -euo pipefail

# Usage: move_status.sh <board-item-id> <backlog|ready|in_progress|in_review|done>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
item_id="${1:?board item id is required}"
status_name="${2:?status name is required}"
project_id="$(jq -r '.project.node_id' "$CONFIG")"
status_field="$(jq -r '.fields.status.field_id' "$CONFIG")"
option_id="$(jq -r ".fields.status.options.$status_name // empty" "$CONFIG")"

if [[ -z "$option_id" ]]; then
  printf 'Unknown board status: %s\n' "$status_name" >&2
  exit 1
fi

gh project item-edit \
  --project-id "$project_id" \
  --id "$item_id" \
  --field-id "$status_field" \
  --single-select-option-id "$option_id"

jq -n --arg item_id "$item_id" --arg moved_to "$status_name" \
  '{item_id: $item_id, moved_to: $moved_to}'
