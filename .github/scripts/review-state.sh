#!/usr/bin/env bash
# Manages incremental review state across pushes to the same PR.
# Cache restore/save is handled by actions/cache in review.yml.
# Usage:
#   review-state.sh restore <focus>
#     Reads last_reviewed_sha. If HEAD differs, writes the diff to a runner
#     temp file and sets INCREMENTAL_DIFF_FILE to its trusted path.
#     On first run (no cache), INCREMENTAL_DIFF_FILE is unset → full review.
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
        if git cat-file -e "$LAST_SHA" 2>/dev/null; then
          # The diff is PR-controlled content. Keep it out of GITHUB_ENV;
          # only the runner-generated file path crosses the step boundary.
          DIFF_FILE=$(mktemp "${RUNNER_TEMP:-/tmp}/review-incremental-diff.XXXXXX")
          git diff "$LAST_SHA..$CURRENT_SHA" > "$DIFF_FILE"
          printf 'INCREMENTAL_DIFF_FILE=%s\n' "$DIFF_FILE" >> "$GITHUB_ENV"
        else
          echo "::notice title=Incremental Review Fallback::Cached SHA $LAST_SHA not found (PR was rebased?) — running full review"
        fi
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
