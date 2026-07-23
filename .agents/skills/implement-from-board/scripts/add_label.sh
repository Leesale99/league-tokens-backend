#!/usr/bin/env bash
set -euo pipefail

# Add a label to a GitHub issue.
# Usage: add_label.sh <issue_number> <label_name>

ISSUE_NUM="$1"
LABEL="$2"

gh issue edit "$ISSUE_NUM" --add-label "$LABEL" 2>/dev/null
echo "{\"labeled\": true, \"issue\": $ISSUE_NUM, \"label\": \"$LABEL\"}"
