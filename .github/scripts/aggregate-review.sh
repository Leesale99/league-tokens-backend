#!/usr/bin/env bash
set -euo pipefail

RESULTS="## Code Review Results
| Review | Status |
|--------|--------|
| Quality | ${QUALITY_RESULT:-skipped} |
| Correctness | ${CORRECTNESS_RESULT:-skipped} |
| Security | ${SECURITY_RESULT:-skipped} |
| Quality Depth | ${QUALITY_DEPTH_RESULT:-skipped} |

"

for review in quality correctness security quality-depth; do
  filename="${review}-review-summary"
  summary_file="summaries/${filename}/${filename}.md"

  RESULTS+="<details>
<summary>${review^} Review Summary</summary>

"
  if [ -f "$summary_file" ]; then
    RESULTS+="$(cat "$summary_file")
"
  else
    RESULTS+="No review summary available.
"
  fi
  RESULTS+="</details>

"
done

RESULTS+="<!-- end-review -->"

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
clean_body=$(echo "$current_body" | sed '/^## Code Review Results/,/^<!-- end-review -->$/d')

gh pr edit "$PR_NUMBER" --repo "$REPO" --body "${clean_body}

${RESULTS}"
