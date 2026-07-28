#!/usr/bin/env bash
# Aggregates review summaries from parallel review matrix jobs into the
# PR description as a rich summary table + checklist.
# Replaces everything between <!-- review-summary-start --> and
# <!-- review-summary-end --> markers.
# Also outputs a top-level comment with expandable focus breakdowns.
set -euo pipefail

FOCI=("quality" "correctness" "security" "quality-depth")

# ── Helpers ──────────────────────────────────────────────────────────

section_lines() {
  local file=$1 h1=$2 h2=$3
  [ ! -f "$file" ] && return 1
  awk -v h1="$h1" -v h2="$h2" '
    $0 ~ h1 { found=1; next }
    found && $0 ~ h2 { found=0; exit }
    found { print }
  ' "$file"
}

count_items() {
  grep -c '^- \[' 2>/dev/null || echo 0
}

compute_effort() {
  local add=$1 del=$2 files=$3
  if   [ "$files" -le 3 ]  && [ "$add" -le 50 ];     then echo 1
  elif [ "$files" -le 8 ]  && [ "$add" -le 200 ];    then echo 2
  elif [ "$files" -le 15 ] && [ "$add" -le 500 ];    then echo 3
  elif [ "$files" -le 30 ] && [ "$add" -le 1200 ];   then echo 4
  else echo 5
  fi
}

# ── Deduplication helpers ────────────────────────────────────────────

declare -A SEEN_PAIRS

seen_before() {
  [ -n "${SEEN_PAIRS[$1:$2]:-}" ]
}

mark_seen() {
  SEEN_PAIRS["$1:$2"]="$3"
}

# ── Parse PR info ────────────────────────────────────────────────────

pr_json=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json additions,deletions,files,title,body 2>/dev/null || echo '{}')

additions=$(echo "$pr_json" | jq -r '.additions // 0')
deletions=$(echo "$pr_json" | jq -r '.deletions // 0')
files=$(echo "$pr_json" | jq -r '.files | length // 0')
title=$(echo "$pr_json" | jq -r '.title // ""')
effort=$(compute_effort "$additions" "$deletions" "$files")

# ── Collect per-focus stats ──────────────────────────────────────────

declare -A b_count i_count s_count
TOTAL_BLOCKING=0
TOTAL_IMPORTANT=0
TOTAL_SUGGESTION=0
any_run=0

for focus in "${FOCI[@]}"; do
  sf="summaries/${focus}-summary/${focus}-review-summary.md"
  if [ ! -f "$sf" ]; then
    b_count[$focus]=-1  # sentinel for "skipped"
    continue
  fi
  any_run=1
  b_count[$focus]=$(section_lines "$sf" "🔴 Blocking" "🟠 Important" | count_items)
  i_count[$focus]=$(section_lines "$sf" "🟠 Important" "🟡 Suggestion" | count_items)
  s_count[$focus]=$(section_lines "$sf" "🟡 Suggestion" "---" | count_items)

  TOTAL_BLOCKING=$((TOTAL_BLOCKING + b_count[$focus]))
  TOTAL_IMPORTANT=$((TOTAL_IMPORTANT + i_count[$focus]))
  TOTAL_SUGGESTION=$((TOTAL_SUGGESTION + s_count[$focus]))
done

# ── Build PR body summary ────────────────────────────────────────────

out=()
out+=("<!-- review-summary-start -->")
out+=("")
out+=("## AI Review Summary")
out+=("")
out+=("**Review effort**: ${effort}/5 (${files} files, +${additions}/${deletions} lines)")
out+=("")
out+=("### Changes")
out+=("")
out+=("> **${title}**")
out+=("")
out+=("### Findings")
out+=("")
out+=("| Focus | 🔴 Blocking | 🟠 Important | 🟡 Suggestion | ✅ Clean |")
out+=("|:---|:---:|:---:|:---:|:---:|")

for focus in "${FOCI[@]}"; do
  bv=${b_count[$focus]:--1}
  if [ "$bv" -eq -1 ]; then
    out+=("| ${focus^} | _skipped_ | _skipped_ | _skipped_ | — |")
    continue
  fi
  b=${b_count[$focus]}
  i=${i_count[$focus]}
  s=${s_count[$focus]}

  clean_mark="✅"
  [ "$b" -gt 0 ] && clean_mark="—"
  [ "$i" -gt 0 ] && clean_mark="—"
  [ "$s" -gt 0 ] && clean_mark="—"

  out+=("| ${focus^} | ${b} | ${i} | ${s} | ${clean_mark} |")
done

# ── Checklist sections with deduplication ────────────────────────────

build_checklist_section() {
  local severity_total=$1 header=$2 start_header=$3 end_header=$4

  if [ "$severity_total" -eq 0 ]; then
    out+=("")
    out+=("### $header")
    out+=("")
    out+=("None")
    return
  fi

  local first_focus=1
  for focus in "${FOCI[@]}"; do
    local bv=${b_count[$focus]:--1}; [ "$bv" -eq -1 ] && continue

    local sf="summaries/${focus}-summary/${focus}-review-summary.md"
    local items
    items=$(section_lines "$sf" "$start_header" "$end_header" 2>/dev/null || true)

    if [ -z "$items" ]; then
      [ "$first_focus" -eq 0 ] && { first_focus=0; continue; }
      continue
    fi

    if [ "$first_focus" -eq 1 ]; then
      out+=("")
      out+=("### $header")
      out+=("")
      first_focus=0
    fi

    while IFS= read -r line; do
      case "$line" in
        "- [ "*)
          local path_line path lineno
          path_line=$(echo "$line" | sed 's/^- \[ \] `\?\(.*\)`\? —.*/\1/')
          path=$(echo "$path_line" | cut -d: -f1)
          lineno=$(echo "$path_line" | cut -d: -f2)

          if [ -n "$path" ] && [ -n "$lineno" ] && seen_before "$path" "$lineno"; then
            echo "::notice::Dedup ${path}:${lineno} — already in ${SEEN_PAIRS[$path:$lineno]}, skip $focus"
            continue
          fi
          [ -n "$path" ] && [ -n "$lineno" ] && mark_seen "$path" "$lineno" "$focus"

          local lbl=""
          case "$line" in *"*[$focus]*"*) ;; *) lbl=" *[$focus]*" ;; esac
          out+=("${line}${lbl}")
          ;;
      esac
    done <<< "$items"
  done
}

build_checklist_section "$TOTAL_BLOCKING"  "🔴 Blocking — must fix before merge"     "🔴 Blocking"   "🟠 Important"
build_checklist_section "$TOTAL_IMPORTANT" "🟠 Important — should fix before merge"    "🟠 Important"  "🟡 Suggestion"
build_checklist_section "$TOTAL_SUGGESTION" "🟡 Suggestion — nice to have"              "🟡 Suggestion" "---"

# ── Footer ───────────────────────────────────────────────────────────

out+=("")
out+=("---")
out+=("*Inline comments with code suggestions in the [Files changed](#files) tab.*")
out+=("[View workflow run →](https://github.com/$REPO/actions/runs/$RUN_ID)")
out+=("")
out+=("<!-- review-summary-end -->")

build=$(printf '%s\n' "${out[@]}")

# ── Build top-level comment body ─────────────────────────────────────

comment_lines=()
comment_lines+=("")
comment_lines+=("<!-- aggregate-review-summary -->")
comment_lines+=("")
comment_lines+=("### 🔍 Review Summary")
comment_lines+=("")

# Summary stats line
comment_lines+=("${TOTAL_BLOCKING} blocking / ${TOTAL_IMPORTANT} important / ${TOTAL_SUGGESTION} suggestion across ${any_run} review focus areas")
comment_lines+=("")

for focus in "${FOCI[@]}"; do
  bv=${b_count[$focus]:--1}; [ "$bv" -eq -1 ] && continue

  sf="summaries/${focus}-summary/${focus}-review-summary.md"
  if [ -f "$sf" ]; then
    b=${b_count[$focus]}; i=${i_count[$focus]}; s=${s_count[$focus]}
    comment_lines+=("<details>")
    comment_lines+=("<summary><strong>${focus^}</strong> (${b}B / ${i}I / ${s}S)</summary>")
    comment_lines+=("")
    comment_lines+=("$(cat "$sf")")
    comment_lines+=("")
    comment_lines+=("</details>")
    comment_lines+=("")
  fi
done

comment_lines+=("[View workflow run →](https://github.com/$REPO/actions/runs/$RUN_ID)")
comment_body=$(printf '%s\n' "${comment_lines[@]}")

# ── Inject into PR body ──────────────────────────────────────────────

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')

if echo "$current_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$current_body" | \
    sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
else
  clean_body="$current_body"
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" \
  --body "${clean_body}"$'\n\n'"${build}"

# ── Post or update top-level comment ─────────────────────────────────

# Find existing aggregate comment from this bot
existing_comment_id=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq '.[] | select(.body | contains("<!-- aggregate-review-summary -->")) | .id' 2>/dev/null | head -1)

tmp_body=$(mktemp)
printf '%s\n' "$comment_body" > "$tmp_body"

if [ -n "${existing_comment_id:-}" ]; then
  jq -n --rawfile body "$tmp_body" '{body: $body}' | \
    gh api "repos/$REPO/issues/comments/$existing_comment_id" \
    -X PATCH --input - >/dev/null
  echo "::notice::Updated existing review summary comment #$existing_comment_id"
else
  gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file "$tmp_body"
  echo "::notice::Posted new review summary comment"
fi

rm -f "$tmp_body"
