#!/usr/bin/env bash
set -euo pipefail

status_emoji() {
  case "$1" in
    success) echo "✅ pass" ;;
    failure) echo "❌ failure" ;;
    skipped) echo "⏭️ skipped" ;;
    cancelled) echo "🚫 cancelled" ;;
    *) echo "❓ unknown" ;;
  esac
}

cat <<BODYEOF > /tmp/pr-body.md
## CI Review Status

| Review | Status |
|--------|--------|
| Quality | $(status_emoji "$QUALITY_RESULT") |
| Correctness | $(status_emoji "$CORRECTNESS_RESULT") |
| Security | $(status_emoji "$SECURITY_RESULT") |
| Quality-Depth | $(status_emoji "$QUALITY_DEPTH_RESULT") |

[View workflow run](https://github.com/${REPO}/actions/runs/${RUN_ID})

---

BODYEOF

has_summaries=false
for type in quality quality-depth security correctness; do
  file="summaries/${type}-review-summary/${type}-review-summary.md"
  if [ -f "$file" ] && [ -s "$file" ]; then
    has_summaries=true
    break
  fi
done

if $has_summaries; then
  echo "## Aggregated Review Summaries" >> /tmp/pr-body.md
  echo "" >> /tmp/pr-body.md

  for type in quality quality-depth security correctness; do
    file="summaries/${type}-review-summary/${type}-review-summary.md"
    if [ -f "$file" ] && [ -s "$file" ]; then
      title=$(head -1 "$file" | sed 's/^#* *//')
      echo "<details>" >> /tmp/pr-body.md
      echo "<summary><b>${title}</b></summary>" >> /tmp/pr-body.md
      echo "" >> /tmp/pr-body.md
      tail -n +2 "$file" >> /tmp/pr-body.md
      echo "" >> /tmp/pr-body.md
      echo "</details>" >> /tmp/pr-body.md
      echo "" >> /tmp/pr-body.md
    fi
  done
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" --body-file /tmp/pr-body.md
