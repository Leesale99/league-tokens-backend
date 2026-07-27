#!/usr/bin/env bash
# Aggregates review summaries from parallel review matrix jobs into the
# PR description as a rich summary table + checklist.
# Replaces everything between <!-- review-summary-start --> and
# <!-- review-summary-end --> markers.
set -euo pipefail

FOCI=("quality" "correctness" "security" "quality-depth")
FOCI_LABELS=("Quality" "Correctness" "Security" "Quality Depth")

# ── Helpers ──────────────────────────────────────────────────────────

# Read a section from a markdown file between two headers.
# Usage: section_lines <file> <header1> <header2>
# Prints lines between the first occurrence of header1 and the next header2
# (or end of file). Returns 1 if header1 not found.
section_lines() {
  local file=$1 h1=$2 h2=$3
  [ ! -f "$file" ] && return 1
  awk -v h1="$h1" -v h2="$h2" '
    $0 ~ h1 { found=1; next }
    found && $0 ~ h2 { found=0; exit }
    found { print }
  ' "$file"
}

# Count non-empty, non-"None" lines in section output
count_items() { grep -c '^- \[' 2>/dev/null || echo 0; }

# ── Compute review effort from PR diff stats ─────────────────────────

compute_effort() {
  local add del files
  add=$1; del=$2; files=$3
  if   [ "$files" -le 3 ]  && [ "$add" -le 50 ];     then echo 1
  elif [ "$files" -le 8 ]  && [ "$add" -le 200 ];    then echo 2
  elif [ "$files" -le 15 ] && [ "$add" -le 500 ];    then echo 3
  elif [ "$files" -le 30 ] && [ "$add" -le 1200 ];   then echo 4
  else echo 5
  fi
}

# ── Build the summary body ───────────────────────────────────────────

BUILD="<!-- review-summary-start -->

## AI Review Summary
"

# — Review effort
pr_json=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json additions,deletions,files,title,body 2>/dev/null || echo '{}')

additions=$(echo "$pr_json" | jq -r '.additions // 0')
deletions=$(echo "$pr_json" | jq -r '.deletions // 0')
files=$(echo "$pr_json" | jq -r '.files | length // 0')
title=$(echo "$pr_json" | jq -r '.title // ""')
effort=$(compute_effort "$additions" "$deletions" "$files")

BUILD+="
**Review effort**: ${effort}/5 (${files} files, +${additions}/−${deletions} lines)

### Changes

> **${title}**

"

# — Build findings table
BUILD+="### Findings

| Focus | 🔴 Blocking | 🟠 Important | 🟡 Suggestion | ✅ Clean |
|:---|:---:|:---:|:---:|:---:|
"

declare -A b_count i_count s_count
TOTAL_BLOCKING=0
TOTAL_IMPORTANT=0
TOTAL_SUGGESTION=0

for focus in "${FOCI[@]}"; do
  sf="summaries/${focus}-summary/${focus}-review-summary.md"
  if [ ! -f "$sf" ]; then
    BUILD+="| ${focus^} | _skipped_ | _skipped_ | _skipped_ | — |\n"
    continue
  fi

  b=$(section_lines "$sf" "🔴 Blocking" "🟠 Important" | count_items)
  i=$(section_lines "$sf" "🟠 Important" "🟡 Suggestion" | count_items)
  s=$(section_lines "$sf" "🟡 Suggestion" "---" | count_items)

  b_count[$focus]=$b; i_count[$focus]=$i; s_count[$focus]=$s
  TOTAL_BLOCKING=$((TOTAL_BLOCKING + b))
  TOTAL_IMPORTANT=$((TOTAL_IMPORTANT + i))
  TOTAL_SUGGESTION=$((TOTAL_SUGGESTION + s))

  clean_mark="✅"
  [ "$b" -gt 0 ] && clean_mark="—"
  [ "$i" -gt 0 ] && clean_mark="—"
  [ "$s" -gt 0 ] && clean_mark="—"

  BUILD+="| ${focus^} | ${b:-—} | ${i:-—} | ${s:-—} | ${clean_mark}\n"
done

# — Merge checklist items by severity
BUILD+="

### Reviewer checklist
"

if [ "$TOTAL_BLOCKING" -gt 0 ]; then
  BUILD+="
#### 🔴 Blocking — must fix before merge
"
  for focus in "${FOCI[@]}"; do
    sf="summaries/${focus}-summary/${focus}-review-summary.md"
    [ -f "$sf" ] || continue
    items=$(section_lines "$sf" "🔴 Blocking" "🟠 Important")
    while IFS= read -r line; do
      case "$line" in
        "- [ "*)
          # Append focus label if not already present
          case "$line" in *"*[${focus^}]*"*) ;; *) line="$line *[${focus^}]*" ;; esac
          BUILD+="${line}\n"
          ;;
      esac
    done <<< "$items"
  done
else
  BUILD+="
#### 🔴 Blocking — must fix before merge
None
"
fi

if [ "$TOTAL_IMPORTANT" -gt 0 ]; then
  BUILD+="
#### 🟠 Important — should fix before merge
"
  for focus in "${FOCI[@]}"; do
    sf="summaries/${focus}-summary/${focus}-review-summary.md"
    [ -f "$sf" ] || continue
    items=$(section_lines "$sf" "🟠 Important" "🟡 Suggestion")
    while IFS= read -r line; do
      case "$line" in
        "- [ "*)
          case "$line" in *"*[${focus^}]*"*) ;; *) line="$line *[${focus^}]*" ;; esac
          BUILD+="${line}\n"
          ;;
      esac
    done <<< "$items"
  done
else
  BUILD+="
#### 🟠 Important — should fix before merge
None
"
fi

if [ "$TOTAL_SUGGESTION" -gt 0 ]; then
  BUILD+="
#### 🟡 Suggestion — nice to have
"
  for focus in "${FOCI[@]}"; do
    sf="summaries/${focus}-summary/${focus}-review-summary.md"
    [ -f "$sf" ] || continue
    items=$(section_lines "$sf" "🟡 Suggestion" "---")
    while IFS= read -r line; do
      case "$line" in
        "- [ "*)
          case "$line" in *"*[${focus^}]*"*) ;; *) line="$line *[${focus^}]*" ;; esac
          BUILD+="${line}\n"
          ;;
      esac
    done <<< "$items"
  done
else
  BUILD+="
#### 🟡 Suggestion — nice to have
None
"
fi

# — Footer
BUILD+="

---
*Inline comments with code suggestions in the [Files changed](#files) tab.*
[View workflow run →](https://github.com/$REPO/actions/runs/$RUN_ID)

<!-- review-summary-end -->"

# ── Inject into PR body ──────────────────────────────────────────────

current_body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body -q '.body')

# Replace content between markers, or prepend
if echo "$current_body" | grep -q '<!-- review-summary-start -->'; then
  clean_body=$(echo "$current_body" | \
    sed '/<!-- review-summary-start -->/,/<!-- review-summary-end -->/d')
else
  clean_body="$current_body"
fi

gh pr edit "$PR_NUMBER" --repo "$REPO" \
  --body "${clean_body}"$'\n\n'"${BUILD}"
