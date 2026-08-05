#!/usr/bin/env bash
# Phase B+C: Aggregates review comments and requirements checklist into
# a combined report, publishes to PR body, manages all labels, and runs
# the merge gate check. Runs as the sink job after all Phase A jobs.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HAS_GO="${HAS_GO:-false}"
NO_ISSUE="${NO_ISSUE:-false}"

# ═══════════════════════════════════════════════════════════════════════
# Section B1 — Aggregate review comments (if Go files present)
# ═══════════════════════════════════════════════════════════════════════

total_blocking=0
review_section=""
usage_section=""

if [ "$HAS_GO" = "true" ]; then
  echo "Aggregating review comments ..."

  # Exclude comments in resolved or outdated review threads. The REST pull
  # comments API does not expose thread state, so resolve it via GraphQL.
  excluded_ids=$(gh api graphql \
    -f query='query($owner: String!, $repo: String!, $pr: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { isResolved isOutdated comments(first: 100) { nodes { databaseId } } } } } } }' \
    -F owner="${REPO%/*}" -F repo="${REPO#*/}" -F pr="$PR_NUMBER" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isOutdated or .isResolved) | .comments.nodes[].databaseId]' 2>/dev/null || true)
  excluded_ids="${excluded_ids:-[]}"
  if [ "$excluded_ids" != "[]" ]; then
    echo "Excluding $(echo "$excluded_ids" | jq 'length') comment(s) in resolved/outdated threads."
  fi

  comments_raw="$tmp/comments.jsonl"

  # Only open comments count: not replies, not on outdated diffs (line null),
  # not in resolved/outdated threads.
  gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq "
    .[]
    | select(.user.login == \"github-actions[bot]\")
    | select(.body | test(\"\\\\*\\\\*\\\\[(blocking|important|suggestion)\\\\]\"))
    | select(.in_reply_to_id == null)
    | select(.line != null)
    | select(.id as \$cid | $excluded_ids | index(\$cid) == null)
    | {body: .body, path: .path, line: .line}
  " > "$comments_raw"

  all_findings='[]'

  while IFS= read -r raw; do
    body=$(echo "$raw" | jq -r '.body')
    path=$(echo "$raw" | jq -r '.path')
    line=$(echo "$raw" | jq -r '.line')

    first_line=$(echo "$body" | head -1)

    case "$first_line" in
      *'**[blocking]'*) sev="blocking" ;;
      *'**[important]'*) sev="important" ;;
      *'**[suggestion]'*) sev="suggestion" ;;
      *) continue ;;
    esac

    title=$(echo "$first_line" | sed 's/^\*\*\['"$sev"'\] — //;s/\*\*$//')

    desc=$(echo "$body" | sed '1,2d' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//' | head -c 200)

    if [ -n "$title" ] && [ -n "$desc" ]; then
      full_desc="$title. $desc"
    elif [ -n "$title" ]; then
      full_desc="$title"
    else
      full_desc="$desc"
    fi

    all_findings=$(echo "$all_findings" | jq -c \
      --arg sev "$sev" \
      --arg path "$path" \
      --argjson line "$line" \
      --arg desc "$full_desc" \
      '. + [{severity: $sev, path: $path, line: $line, description: $desc}]' \
      2>/dev/null || echo "$all_findings")

  done < "$comments_raw"

  all_findings=$(echo "$all_findings" | jq -c '
    group_by({path, line}) |
    map(
      sort_by(
        if .severity == "blocking" then 0
        elif .severity == "important" then 1
        else 2 end
      ) | .[0]
    )
  ' 2>/dev/null || echo '[]')

  total_blocking=$(echo "$all_findings" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo 0)
  total_important=$(echo "$all_findings" | jq '[.[] | select(.severity == "important")] | length' 2>/dev/null || echo 0)
  total_suggestion=$(echo "$all_findings" | jq '[.[] | select(.severity == "suggestion")] | length' 2>/dev/null || echo 0)

  out=()
  out+=("<!-- review-summary-start -->")
  out+=("")
  out+=("## AI Review Summary")
  out+=("")
  out+=("🔴 ${total_blocking} blocking · 🟠 ${total_important} important · 🟡 ${total_suggestion} suggestion")
  out+=("")

  if [ "$total_blocking" -eq 0 ] && [ "$total_important" -eq 0 ] && [ "$total_suggestion" -eq 0 ]; then
    out+=("No issues found.")
  else
    for sev_label in "blocking:### 🔴 Blocking" "important:### 🟠 Important" "suggestion:### 🟡 Suggestion"; do
      sev="${sev_label%%:*}"
      heading="${sev_label##*:}"
      items=$(echo "$all_findings" | jq -r \
        '[.[] | select(.severity == "'"$sev"'")] | .[] | "- [ ] `\(.path):\(.line)` — \(.description)"' \
        2>/dev/null || true)
      if [ -n "${items:-}" ]; then
        out+=("$heading")
        out+=("")
        while IFS= read -r l; do out+=("$l"); done <<< "$items"
        out+=("")
      fi
    done
  fi

  # Token usage per review job (from uploaded review-usage-* artifacts).
  USAGE_DIR="${USAGE_DIR:-}"
  usage_rows=""
  if [ -n "$USAGE_DIR" ] && [ -d "$USAGE_DIR" ]; then
    usage_rows=$(jq -sr 'sort_by(.job) | .[] | "| \(.job) | \(.model) | \(.usage.input) | \(.usage.cacheRead) | \(.usage.output) | \(.usage.cacheWrite) | \(.usage.total) | $\((.usage.cost * 10000 | round) / 10000) |"' "$USAGE_DIR"/*/review-usage.json 2>/dev/null || true)
  fi
  usage_section=""
  if [ -n "$usage_rows" ]; then
    usage_section=$(printf '%s\n' \
      "<!-- token-usage-start -->" \
      "" \
      "## Token Usage" \
      "" \
      "| Job | Model | Input | Cache read | Output | Cache write | Total | Cost |" \
      "|---|---|---|---|---|---|---|---|" \
      "$usage_rows" \
      "" \
      "<!-- token-usage-end -->")
  fi

  out+=("---")
  out+=("[View workflow →](https://github.com/$REPO/actions/runs/$RUN_ID)")
  out+=("")
  out+=("<!-- review-summary-end -->")

  review_section=$(printf '%s\n' "${out[@]}")
  echo "Review summary built (${total_blocking} blocking, ${total_important} important, ${total_suggestion} suggestion)."
else
  echo "No Go files changed — skipping review summary."
fi

# ═══════════════════════════════════════════════════════════════════════
# Section B2 — Build combined report
# ═══════════════════════════════════════════════════════════════════════

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
clean_body="$current_body"

if echo "$clean_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
fi

if echo "$clean_body" | grep -q '<!-- requirements-review-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/d')
fi

if echo "$clean_body" | grep -q '<!-- token-usage-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- token-usage-start -->/,/<!-- token-usage-end -->/d')
fi

new_body="$clean_body"

# Section order: 1) Requirements summary, 2) AI review summary, 3) Token usage.
if [ "$NO_ISSUE" != "true" ] && [ -n "${CHECKLIST:-}" ]; then
  new_body="${new_body}"$'\n\n'"${CHECKLIST}"
fi

if [ -n "$review_section" ]; then
  new_body="${new_body}"$'\n\n'"${review_section}"
fi

if [ -n "$usage_section" ]; then
  new_body="${new_body}"$'\n\n'"${usage_section}"
fi

# ═══════════════════════════════════════════════════════════════════════
# Section C1 — Publish combined report to PR body
# ═══════════════════════════════════════════════════════════════════════

gh pr edit "$PR_NUMBER" --repo "$REPO" --body "$new_body"
echo "PR body updated."

# ═══════════════════════════════════════════════════════════════════════
# Section C2 — Set all labels
# ═══════════════════════════════════════════════════════════════════════

# Code review axis: review-skipped ↔ review-passed / review-failed
if [ "$HAS_GO" != "true" ]; then
  echo "No Go files — applying review-skipped."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label review-skipped 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label review-passed 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label review-failed 2>/dev/null || true
else
  echo "Go files present — removing review-skipped."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label review-skipped 2>/dev/null || true
  if [ "$total_blocking" -eq 0 ]; then
    echo "No blocking issues — applying review-passed."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label review-passed 2>/dev/null || true
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label review-failed 2>/dev/null || true
  else
    echo "$total_blocking blocking issue(s) — applying review-failed."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label review-failed 2>/dev/null || true
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label review-passed 2>/dev/null || true
  fi
fi

# Requirements axis: requirements-skipped ↔ requirements-verified / requirements-missing
if [ "$NO_ISSUE" = "true" ]; then
  echo "No linked issue — applying requirements-skipped."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-skipped 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-missing 2>/dev/null || true
else
  echo "Linked issue present — removing requirements-skipped."
  gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-skipped 2>/dev/null || true

  if [ -n "${CHECKLIST:-}" ]; then
    printf '%s\n' "$CHECKLIST" > "$tmp/checklist.txt"
    UNCHECKED=$(grep -F -c '[ ]' "$tmp/checklist.txt" || true)
    if [ "${UNCHECKED:-0}" -eq 0 ]; then
      echo "All requirements met — applying requirements-verified."
      gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-verified 2>/dev/null || true
      gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-missing 2>/dev/null || true
    else
      echo "$UNCHECKED requirement(s) not met — applying requirements-missing."
      gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-missing 2>/dev/null || true
      gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
    fi
  else
    echo "No checklist content — applying requirements-missing."
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label requirements-missing 2>/dev/null || true
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label requirements-verified 2>/dev/null || true
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Section C3 — Gate check
# ═══════════════════════════════════════════════════════════════════════

HAS_GO_RESULT="${HAS_GO_RESULT:-skipped}"
CI_RESULT="${CI_RESULT:-skipped}"
VERIFY_RESULT="${VERIFY_RESULT:-skipped}"
DISMISS_RESULT="${DISMISS_RESULT:-skipped}"
REVIEW_RESULT="${REVIEW_RESULT:-skipped}"

# Any pipeline job that failed (or timed out / was cancelled) blocks the merge,
# even if the PR already carries passing labels. The user must re-trigger the
# workflow and fix the failing job before the PR can merge.
FAILED=""
for RESULT in HAS_GO_RESULT CI_RESULT VERIFY_RESULT DISMISS_RESULT REVIEW_RESULT; do
  VALUE="${!RESULT}"
  if [ "$VALUE" != "success" ] && [ "$VALUE" != "skipped" ]; then
    FAILED="${FAILED}${RESULT}=${VALUE} "
  fi
done

if [ -n "$FAILED" ]; then
  echo "::error::One or more pipeline jobs failed: ${FAILED}— merge blocked until the workflow is re-run and all jobs pass."
  exit 1
fi

LABELS=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)

if ! echo "$LABELS" | grep -qE '^review-passed$|^review-skipped$'; then
  echo "::error::Missing review-passed or review-skipped label (review-failed)"
  exit 1
fi

if ! echo "$LABELS" | grep -qE '^requirements-verified$|^requirements-skipped$'; then
  echo "::error::Missing requirements-verified or requirements-skipped label (requirements-missing)"
  exit 1
fi

echo "::notice::All merge gates passed."
