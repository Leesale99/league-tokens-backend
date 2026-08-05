#!/usr/bin/env bash
set -euo pipefail

# Usage: open_pr.sh <issue-number> <title> <summary>
# Requires all work committed. Pushes the current branch and opens the PR.

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
if [[ -z "$branch" || "$branch" == "main" ]]; then
  echo 'A non-main feature branch is required to open a PR.' >&2
  exit 1
fi

git push --set-upstream origin "$branch"
pr_url="$(gh pr create --title "$title" --body "$(cat <<EOF
Closes #$issue_number

$summary
EOF
)")"

jq -n --arg pr_url "$pr_url" --arg branch "$branch" '{pr_url: $pr_url, branch: $branch}'
