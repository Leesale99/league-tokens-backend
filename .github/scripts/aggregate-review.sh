#!/usr/bin/env bash
# Aggregates review summaries from parallel review matrix jobs into the
# PR description. Replaces everything between <!-- review-summary-start -->
# and <!-- review-summary-end --> markers. On first run, injects the section.
# Matrix instance results aren't addressable from the aggregate job, so
# status is derived from whether each summary artifact exists.
set -euo pipefail

RESULTS="<!-- review-summary-start -->

## AI Review Summary

"
total_foci=0
passed_foci=0

for focus in quality correctness security quality-depth; do
  total_foci=$((total_foci + 1))
  # Artifact name is ${focus}-summary, file inside is ${focus}-review-summary.md
  summary_file="summaries/${focus}-summary/${focus}-review-summary.md"

  RESULTS+="<details>
<summary>${focus^} Review Summary</summary>

"
  if [ -f "$summary_file" ]; then
    RESULTS+="$(cat "$summary_file")
"
    passed_foci=$((passed_foci + 1))
  else
    RESULTS+="No review summary available.
"
  fi
  RESULTS+="</details>

"
done

RESULTS+="**${passed_foci}/${total_foci}** review foci completed successfully.

<!-- review-summary-end -->"

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')

# Replace content between markers, or append if markers don't exist yet
if echo "$current_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$current_body" | sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
else
  clean_body="$current_body"
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" --body "${clean_body}

${RESULTS}"
