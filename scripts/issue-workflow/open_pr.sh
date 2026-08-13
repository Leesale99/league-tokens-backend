#!/usr/bin/env bash
set -euo pipefail

# Usage: open_pr.sh <issue-number> <title> <summary>
# Requires all work committed and the current branch named <prefix>/<issue>-*
# (matching create_branch.sh). Pushes the branch, opens the PR, and kills the
# issue's leftover context/final-review tmux sessions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

issue_number="${1:?issue number is required}"
title="${2:?PR title is required}"
summary="${3:?PR summary is required}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'Tracked changes are present; review and commit all intended changes before opening a PR.' >&2
  exit 1
fi

# Workflow records are intentionally local until a task chooses to commit them.
# Do not let unrelated untracked product files be mistaken for completed work.
unexpected_untracked="$(git status --porcelain --untracked-files=all | awk '$1 == "??" {print $2}' | grep -Fv "docs/issue-workflows/$issue_number/" || true)"
if [[ -n "$unexpected_untracked" ]]; then
  echo 'Untracked files outside this issue workflow record are present; resolve them before opening a PR.' >&2
  exit 1
fi

branch="$(git branch --show-current)"
prefix="$(jq -r '.branch.prefix' "$CONFIG")"
if [[ "$branch" != "$prefix/$issue_number-"* ]]; then
  printf 'Current branch %s does not match %s/%s-*; refusing to open the PR (it would claim to close #%s).\n' \
    "$branch" "$prefix" "$issue_number" "$issue_number" >&2
  exit 1
fi

git push --set-upstream origin "$branch"
pr_url="$(gh pr create --title "$title" --body "$(cat <<EOF
Closes #$issue_number

$summary
EOF
)")"

# The context and final-review orchestrators are done once the PR exists;
# do not leave their tmux sessions behind.
for session in "issue-$issue_number-context" "issue-$issue_number-final-review"; do
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    printf 'Killed tmux session %s\n' "$session" >&2
  fi
done

jq -n --arg pr_url "$pr_url" --arg branch "$branch" '{pr_url: $pr_url, branch: $branch}'
