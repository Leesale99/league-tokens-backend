#!/usr/bin/env bash
# Usage: cleanup.sh <issue-number>
# Removes the issue's role sandboxes (issue-<N>-*) and its worktree —
# Task 5.2, the ONLY place sandboxes are destroyed. Spike runners print
# this command instead of running it (sandboxes stay alive until archive).
set -euo pipefail

issue="${1:?issue number is required}"
v2="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

removed=0
while read -r s; do
  [[ -n "$s" ]] || continue
  sbx rm --force "$s"
  printf 'cleanup: removed sandbox %s\n' "$s"
  removed=$((removed + 1))
done < <(sbx ls 2>/dev/null | awk -v p="issue-$issue-" '$1 ~ ("^" p) {print $1}')

"$v2/worktree.sh" "$issue" remove >/dev/null 2>&1 || true
printf 'cleanup: issue #%s — %s sandbox(es) removed, worktree removed\n' "$issue" "$removed"
