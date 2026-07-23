#!/usr/bin/env bash
set -euo pipefail

# Remove a label from a GitHub issue.
# Usage: remove_label.sh <issue_number> <label_name>

ISSUE_NUM="$1"
LABEL="$2"

gh issue edit "$ISSUE_NUM" --remove-label "$LABEL" 2>/dev/null
echo "{\"removed\": true, \"issue\": $ISSUE_NUM, \"label\": \"$LABEL\"}"
