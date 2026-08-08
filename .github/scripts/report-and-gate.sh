#!/usr/bin/env bash
# Phase B+C: Aggregates per-focus review findings (artifacts) into ONE
# consolidated review comment + PR-body report, publishes the PR body,
# manages all labels, and runs the merge gate check. Runs as the sink job
# after all Phase A jobs. This is the ONLY job that writes to the PR, so
# comment posting is race-free by construction.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HAS_GO="${HAS_GO:-false}"
NO_ISSUE="${NO_ISSUE:-false}"

# Phase tracking: a bare `set -e` death only prints a line number; this turns
# it into a readable annotation naming the failing phase. (Fatal `set -u`
# errors aren't catchable here and keep bash's native message.)
PHASE="startup"
on_error() {
  echo "::error::report-and-gate.sh failed in phase '${PHASE}' (line $1: $2)" >&2
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

# ═══════════════════════════════════════════════════════════════════════
# Section B1 — Aggregate findings, post one consolidated review, build the
#              PR-body review summary.
# ═══════════════════════════════════════════════════════════════════════

PHASE="B1: aggregate review findings"
total_blocking=0
review_section=""
meta_section=""

if [ "$HAS_GO" = "true" ]; then
  echo "Aggregating review findings ..."

  all_findings=$(FINDINGS_DIR="${FINDINGS_DIR:-}" .github/scripts/aggregate-findings.sh 2>>"$tmp/aggregate.log" || echo '[]')
  cat "$tmp/aggregate.log" >&2 || true

  # Deduplicated by (path, line) in aggregate-findings.sh. Totals drive the
  # posted review, the PR-body summary, and the review-failed label.
  total_findings=$(echo "$all_findings" | jq 'length' 2>/dev/null || echo 0)
  total_blocking=$(echo "$all_findings" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo 0)
  total_important=$(echo "$all_findings" | jq '[.[] | select(.severity == "important")] | length' 2>/dev/null || echo 0)
  total_suggestion=$(echo "$all_findings" | jq '[.[] | select(.severity == "suggestion")] | length' 2>/dev/null || echo 0)

  echo "Aggregated $total_findings finding(s): $total_blocking blocking, $total_important important, $total_suggestion suggestion."

  # ── Manage previous rounds' comments + post one consolidated review ───
  # Only touch comments when all review jobs succeeded; a failed round keeps
  # everything as evidence (the gate fails anyway).
  #
  # Delete + post, relying on GitHub's native behavior for reply detection:
  #   - DELETE a previous round's bot comment → success: it was untouched
  #     superseded noise, gone. This round re-posts the finding if it still
  #     applies.
  #   - DELETE fails (422): the comment has human replies — GitHub refuses to
  #     orphan them, so the thread is kept as engaged history. Resolved or
  #     wontfix threads re-appear as fresh comments each round until fixed;
  #     resolving is the PR owner's job.
  # No reply-detection logic needed — the delete attempt IS the detection.
  # Reactions are not interaction: a reacted-to comment with no replies is
  # deleted too. Submitted review events can't be deleted via the API, so
  # the timeline keeps one "reviewed" entry per round.
  comment_ids='[]'
  case "${REVIEW_RESULT:-success}" in
    success|skipped) review_ok=1 ;;
    *) review_ok=0 ;;
  esac
  if [ "$review_ok" -eq 0 ]; then
    echo "::warning::One or more review jobs failed (REVIEW_RESULT=${REVIEW_RESULT}) — skipping comment management/post, keeping previous comments."
  else
    # Previous rounds' bot comments (id only — enough for the delete loop).
    comments=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq \
      '[.[] | select(.user.login == "github-actions[bot]") | .id]' 2>/dev/null || echo '[]')

    deleted=0
    kept=0
    while read -r id; do
      [ -z "$id" ] && continue
      if gh api "repos/$REPO/pulls/comments/$id" -X DELETE >/dev/null 2>&1; then
        deleted=$((deleted + 1))
      else
        echo "  kept previous round comment #$id (has human replies)"
        kept=$((kept + 1))
      fi
    done < <(echo "$comments" | jq -r '.[]')
    echo "Previous round: deleted $deleted untouched comment(s), kept $kept engaged comment(s)."

    # Snapshot surviving bot comments so we can tell them apart from the ones
    # we post below — kept old threads must not be linked from the summary.
    before_ids=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq \
      '[.[] | select(.user.login == "github-actions[bot]") | {id, path, line}]' 2>/dev/null || echo '[]')

    if [ "$total_findings" -gt 0 ]; then
      echo "$all_findings" | jq -c '{event: "COMMENT", body: "", comments: [.[] | {path, line, body}]}' > "$tmp/review-payload.json"

      if gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --input "$tmp/review-payload.json" >/dev/null 2>"$tmp/post.err"; then
        echo "Posted consolidated review with $total_findings inline comment(s)."
      else
        # A bulk post fails with 422 when a comment's line is not in the current
        # diff (e.g. stale finding from an earlier push). Fall back to one review
        # per comment and skip unanchored lines.
        echo "::warning::Bulk review post failed: $(head -1 "$tmp/post.err" || true) — posting comments individually."
        echo "$all_findings" | jq -c '.[]' | while read -r f; do
          [ -z "$f" ] && continue
          single=$(jq -n --argjson f "$f" '{event: "COMMENT", body: "", comments: [{path: $f.path, line: $f.line, body: $f.body}]}')
          if gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --input <(printf '%s' "$single") >/dev/null 2>&1; then
            echo "  posted $(echo "$f" | jq -r '.path + ":" + ((.line // 0)|tostring)')"
          else
            echo "::warning::Skipped $(echo "$f" | jq -r '.path + ":" + ((.line // 0)|tostring)') — line not in current diff"
          fi
        done
      fi

      # New comment ids = bot comments now minus the kept survivors.
      after_ids=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate --jq \
        '[.[] | select(.user.login == "github-actions[bot]") | {id, path, line}]' 2>/dev/null || echo '[]')
      comment_ids=$(jq -n --argjson after "$after_ids" --argjson before "$before_ids" \
        '($before | map(.id)) as $ids | [ $after[] | select(.id as $i | ($ids | index($i)) == null) ]')
    else
      echo "No findings to post — previous round's untouched comments already deleted."
    fi
  fi

  # ── Build the PR-body review summary section ──────────────────────────
  out=()
  out+=("<!-- review-summary-start -->")
  out+=("")
  out+=("## AI Review Summary")
  out+=("")

  if [ "$total_findings" -eq 0 ]; then
    if [ "$review_ok" -eq 0 ]; then
      out+=("> ⚠️ Review incomplete — one or more review jobs failed.")
      out+=("")
    else
      out+=("No issues found.")
    fi
  else
    if [ "$review_ok" -eq 0 ]; then
      out+=("> ⚠️ Review incomplete — one or more review jobs failed; findings below may be partial.")
      out+=("")
    fi
    # Render one bullet per finding, linked to the posted comment id.
    blocking_items=()
    important_items=()
    suggestion_items=()
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      sev=$(echo "$f" | jq -r '.severity')
      path=$(echo "$f" | jq -r '.path')
      line=$(echo "$f" | jq -r '.line')
      title=$(echo "$f" | jq -r '.title')
      body=$(echo "$f" | jq -r '.body')
      id=$(echo "$comment_ids" | jq -r --arg p "$path" --argjson l "$line" \
        '.[] | select(.path == $p and .line == $l) | .id' | head -1)
      desc=$(echo "$body" | sed '1,2d' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//' | head -c 200)

      if [ -n "$title" ] && [ -n "$desc" ]; then
        full_desc="$title. $desc"
      elif [ -n "$title" ]; then
        full_desc="$title"
      else
        full_desc="$desc"
      fi

      loc="${path}:${line}"
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        item="- [ ] [\`${loc}\`](https://github.com/$REPO/pull/$PR_NUMBER#discussion_r$id) — $full_desc"
      else
        item="- [ ] \`${loc}\` — $full_desc"
      fi
      case "$sev" in
        blocking)   blocking_items+=("$item") ;;
        important)  important_items+=("$item") ;;
        suggestion) suggestion_items+=("$item") ;;
      esac
    done < <(echo "$all_findings" | jq -c '.[]')

    render_details() {
      local heading="$1"; shift
      [ "$#" -eq 0 ] && return 0
      out+=("<details>")
      out+=("<summary>$heading ($#)</summary>")
      out+=("")
      for l in "$@"; do [ -n "$l" ] && out+=("$l"); done
      out+=("")
      out+=("</details>")
      out+=("")
    }
    render_details "🔴 Blocking" "${blocking_items[@]}"
    render_details "🟠 Important" "${important_items[@]}"
    render_details "🟡 Suggestion" "${suggestion_items[@]}"
  fi

  # Pipeline metadata: token usage per review job (from uploaded artifacts).
  USAGE_DIR="${USAGE_DIR:-}"
  usage_rows=""
  if [ -n "$USAGE_DIR" ] && [ -d "$USAGE_DIR" ]; then
    usage_rows=$(jq -sr 'sort_by(.job) | .[] | "| \(.job) | \(.model) | \(.usage.input) | \(.usage.cacheRead) | \(.usage.output) | \(.usage.cacheWrite) | \(.usage.total) | $\((.usage.cost * 10000 | round) / 10000) |"' "$USAGE_DIR"/*/review-usage.json 2>/dev/null || true)
  fi

  if [ -n "$usage_rows" ]; then
    meta_lines=()
    meta_lines+=("<!-- pipeline-meta-start -->")
    meta_lines+=("")
    meta_lines+=("<details>")
    meta_lines+=("<summary>Last review round</summary>")
    meta_lines+=("")
    meta_lines+=("### Token Usage")
    meta_lines+=("")
    meta_lines+=("| Job | Model | Input | Cache read | Output | Cache write | Total | Cost |")
    meta_lines+=("|---|---|---|---|---|---|---|---|")
    meta_lines+=("$usage_rows")
    meta_lines+=("")
    meta_lines+=("[View workflow →](https://github.com/$REPO/actions/runs/$RUN_ID)")
    meta_lines+=("")
    meta_lines+=("</details>")
    meta_lines+=("")
    meta_lines+=("<!-- pipeline-meta-end -->")
    meta_section=$(printf '%s\n' "${meta_lines[@]}")
  fi

  out+=("<!-- review-summary-end -->")

  review_section=$(printf '%s\n' "${out[@]}")
  echo "Review summary built (${total_blocking} blocking, ${total_important} important, ${total_suggestion} suggestion)."
else
  echo "No Go files changed — skipping review summary."
fi

# ═══════════════════════════════════════════════════════════════════════
# Section B2 — Build combined report
# ═══════════════════════════════════════════════════════════════════════

PHASE="B2: build combined report"
current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')
clean_body="$current_body"

if echo "$clean_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
fi

if echo "$clean_body" | grep -q '<!-- requirements-review-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- requirements-review-start -->/,/<!-- requirements-review-end -->/d')
fi

if echo "$clean_body" | grep -q '<!-- pipeline-meta-start -->'; then
  clean_body=$(echo "$clean_body" | sed '/<!-- pipeline-meta-start -->/,/<!-- pipeline-meta-end -->/d')
fi

new_body="$clean_body"

# Section order: 1) Requirements summary, 2) AI review summary, 3) Pipeline metadata.
if [ "$NO_ISSUE" != "true" ] && [ -n "${CHECKLIST:-}" ]; then
  new_body="${new_body}"$'\n\n'"${CHECKLIST}"
fi

if [ -n "$review_section" ]; then
  new_body="${new_body}"$'\n\n'"${review_section}"
fi

if [ -n "$meta_section" ]; then
  new_body="${new_body}"$'\n\n'"${meta_section}"
fi

# ═══════════════════════════════════════════════════════════════════════
# Section C1 — Publish combined report to PR body
# ═══════════════════════════════════════════════════════════════════════

PHASE="C1: publish PR body"
gh pr edit "$PR_NUMBER" --repo "$REPO" --body "$new_body"
echo "PR body updated."

# ═══════════════════════════════════════════════════════════════════════
# Section C2 — Set all labels
# ═══════════════════════════════════════════════════════════════════════

PHASE="C2: set labels"
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
    printf '%s\n' "$CHECKLIST" >"$tmp/checklist.txt"
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

PHASE="C3: merge gate check"
HAS_GO_RESULT="${HAS_GO_RESULT:-skipped}"
CI_RESULT="${CI_RESULT:-skipped}"
VERIFY_RESULT="${VERIFY_RESULT:-skipped}"
REVIEW_RESULT="${REVIEW_RESULT:-skipped}"

# Any pipeline job that failed (or timed out / was cancelled) blocks the merge,
# even if the PR already carries passing labels. The user must re-trigger the
# workflow and fix the failing job before the PR can merge.
FAILED=""
for RESULT in HAS_GO_RESULT CI_RESULT VERIFY_RESULT REVIEW_RESULT; do
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
