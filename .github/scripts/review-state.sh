#!/usr/bin/env bash
# Manages incremental review state across pushes to the same PR.
# Cache restore/save is handled by actions/cache in review.yml.
# Usage:
#   review-state.sh restore <focus>
#     Reads last_reviewed_sha. If HEAD differs, sets INCREMENTAL_DIFF env.
#     On first run (no cache), INCREMENTAL_DIFF is unset → full review.
#   review-state.sh save <focus>
#     Writes current HEAD SHA as last_reviewed_sha.
set -euo pipefail

ACTION="$1"
FOCUS="$2"
STATE_DIR=".review-state/${FOCUS}"
FILE="$STATE_DIR/last_sha"

case "$ACTION" in
  restore)
    if [ -f "$FILE" ]; then
      LAST_SHA=$(cat "$FILE")
      CURRENT_SHA=$(git rev-parse HEAD)
      if [ "$LAST_SHA" != "$CURRENT_SHA" ]; then
        DIFF=$(git diff "$LAST_SHA..$CURRENT_SHA")
        DELIM="DIFF_END_${RANDOM}${RANDOM}"
        {
          echo "INCREMENTAL_DIFF<<${DELIM}"
          echo "$DIFF"
          echo "${DELIM}"
        } >> "$GITHUB_ENV"
      fi
    fi
    ;;
  save)
    mkdir -p "$STATE_DIR"
    git rev-parse HEAD > "$FILE"
    ;;
  *)
    echo "Usage: $0 {restore|save} <focus>"
    exit 1
    ;;
esac
