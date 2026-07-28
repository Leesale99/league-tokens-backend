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
  local c
  c=$(grep -c '^- \[' 2>/dev/null || true)
  echo "${c:-0}"
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

# ── Merge helpers — same (path, line) across foci ─────────────────────
# Uses temp files: one per severity bucket.
# Format per line: "path:line␟focus|sev|desc"
# (␟ is unit separator, | separates focus/severity/desc within a finding)

BLOCKING_FILE=$(mktemp)
IMPORTANT_FILE=$(mktemp)
SUGGESTION_FILE=$(mktemp)

cleanup_merge_files() { rm -f "$BLOCKING_FILE" "$IMPORTANT_FILE" "$SUGGESTION_FILE"; }
trap cleanup_merge_files EXIT

merge_file_for_severity() {
  case "$1" in
    MERGED_BLOCKING)  echo "$BLOCKING_FILE" ;;
    MERGED_IMPORTANT) echo "$IMPORTANT_FILE" ;;
    MERGED_SUGGESTION) echo "$SUGGESTION_FILE" ;;
  esac
}

parse_and_merge() {
  local focus=$1 line=$2 bucket_var=$3

  local path lineno desc path_line

  # Extract path:line from backtick-delimited format: `file.go:42`
  if echo "$line" | grep -q '`'; then
    path_line=$(echo "$line" | grep -o '`[^`]*`' | head -1 | tr -d '`')
  else
    # Fallback: " - [ ] file.go:42 — desc"
    path_line=$(echo "$line" | sed 's/^- \[ \] \([^ ]*\) —.*/\1/')
  fi

  path=$(echo "$path_line" | cut -d: -f1)
  lineno=$(echo "$path_line" | cut -d: -f2)
  [ -z "$path" ] || [ -z "$lineno" ] && return 1

  # Extract description (everything after " — ")
  desc=$(echo "$line" | sed 's/^.* — //')
  # Strip trailing focus label: " *[Focus]*" or " *[Focus (🟡)]*"
  desc=$(echo "$desc" | sed 's/ \*\[.*\]\*$//')

  local sev
  case "$bucket_var" in
    MERGED_BLOCKING)  sev="🔴" ;;
    MERGED_IMPORTANT) sev="🟠" ;;
    MERGED_SUGGESTION) sev="🟡" ;;
  esac

  local merge_file key existing
  merge_file=$(merge_file_for_severity "$bucket_var")
  key="$path:$lineno"

  # Check if this key already has an entry in the merge file
  existing=$(grep "^${key}␟" "$merge_file" 2>/dev/null || true)

  if [ -n "$existing" ]; then
    # Append to existing entry
    sed -i "s|^${key}␟.*|${existing}␟${focus}|${sev}|${desc}|" "$merge_file"
  else
    echo "${key}␟${focus}|${sev}|${desc}" >> "$merge_file"
  fi
}

# Count unique entries in a merge file
merged_count() {
  local f=$1
  [ -f "$f" ] && wc -l < "$f" || echo 0
}

emit_merged_section() {
  local f=$1 severity_label=$2

  if [ ! -s "$f" ]; then
    out+=("")
    out+=("### $severity_label")
    out+=("")
    out+=("None")
    return
  fi

  out+=("")
  out+=("### $severity_label")
  out+=("")

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key combined path lineno
    key=$(echo "$line" | cut -d'␟' -f1)
    combined=$(echo "$line" | cut -d'␟' -f2-)
    path=$(echo "$key" | cut -d: -f1)
    lineno=$(echo "$key" | cut -d: -f2)

    local first=1 tags="" desc=""
    # Split entries separated by ␟ into newlines, then parse each
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      f=$(echo "$entry" | cut -d'|' -f1)
      s=$(echo "$entry" | cut -d'|' -f2)
      d=$(echo "$entry" | cut -d'|' -f3-)
      if [ "$first" -eq 1 ]; then
        desc="$d"
        first=0
      fi
      tags="${tags} *[$f ($s)]*"
    done < <(echo "$combined" | tr '␟' '\n')

    out+=("- [ ] \`${path}:${lineno}\` — ${desc}${tags}")
  done < "$f"
}

# ── Parse PR info ────────────────────────────────────────────────────

pr_json=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json additions,deletions,files,title,body 2>/dev/null || echo '{}')

additions=$(echo "$pr_json" | jq -r '.additions // 0')
deletions=$(echo "$pr_json" | jq -r '.deletions // 0')
files=$(echo "$pr_json" | jq -r '.files | length // 0')
title=$(echo "$pr_json" | jq -r '.title // ""')
effort=$(compute_effort "$additions" "$deletions" "$files")

# ── Collect per-focus stats & populate merge buckets ──────────────────

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

  # Populate merge buckets for each severity level
  while IFS= read -r line; do
    [[ "$line" == "- [ "* ]] && parse_and_merge "$focus" "$line" MERGED_BLOCKING
  done < <(section_lines "$sf" "🔴 Blocking" "🟠 Important" 2>/dev/null || true)

  while IFS= read -r line; do
    [[ "$line" == "- [ "* ]] && parse_and_merge "$focus" "$line" MERGED_IMPORTANT
  done < <(section_lines "$sf" "🟠 Important" "🟡 Suggestion" 2>/dev/null || true)

  while IFS= read -r line; do
    [[ "$line" == "- [ "* ]] && parse_and_merge "$focus" "$line" MERGED_SUGGESTION
  done < <(section_lines "$sf" "🟡 Suggestion" "---" 2>/dev/null || true)
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

# ── Emit merged checklist sections ────────────────────────────────────

emit_merged_section "$BLOCKING_FILE"  "🔴 Blocking — must fix before merge"
emit_merged_section "$IMPORTANT_FILE" "🟠 Important — should fix before merge"
emit_merged_section "$SUGGESTION_FILE" "🟡 Suggestion — nice to have"

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

# ── Post top-level comment ────────────────────────────────────────────

tmp_body=$(mktemp)
printf '%s\n' "$comment_body" > "$tmp_body"

gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file "$tmp_body"
echo "::notice::Posted review summary comment"

rm -f "$tmp_body"
