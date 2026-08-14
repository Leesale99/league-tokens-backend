#!/usr/bin/env bash
set -euo pipefail

# Usage: open_pr.sh <issue-number> <title> <summary>
# v2 flow: the feature branch lives in the issue WORKTREE
# (.worktrees/issue-<N>, created by v2/worktree.sh). Requires the worktree
# to exist, be clean, and sit on <prefix>/<issue>-*; pushes from there and
# opens the PR. The main checkout is never touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
REPO_ROOT="$(git rev-parse --show-toplevel)"

issue_number="${1:?issue number is required}"
title="${2:?PR title is required}"
summary="${3:?PR summary is required}"

wt="$REPO_ROOT/.worktrees/issue-$issue_number"
[[ -f "$wt/.git" ]] || { printf 'worktree missing at %s — run v2/worktree.sh %s <slug> first\n' "$wt" "$issue_number" >&2; exit 1; }

if ! git -C "$wt" diff --quiet || ! git -C "$wt" diff --cached --quiet; then
  echo 'Tracked changes are present in the worktree; review and commit all intended changes before opening a PR.' >&2
  exit 1
fi
if [[ -n "$(git -C "$wt" status --porcelain --untracked-files=all)" ]]; then
  echo 'Untracked files are present in the worktree; resolve them before opening a PR.' >&2
  exit 1
fi

branch="$(git -C "$wt" branch --show-current)"
prefix="$(jq -r '.branch.prefix' "$CONFIG")"
if [[ "$branch" != "$prefix/$issue_number-"* ]]; then
  printf 'Worktree branch %s does not match %s/%s-*; refusing to open the PR (it would claim to close #%s).\n' \
    "$branch" "$prefix" "$issue_number" "$issue_number" >&2
  exit 1
fi

git -C "$wt" push --set-upstream origin "$branch"
pr_url="$(cd "$wt" && gh pr create --title "$title" --body "$(cat <<EOF
Closes #$issue_number

$summary
EOF
)")"

jq -n --arg pr_url "$pr_url" --arg branch "$branch" '{pr_url: $pr_url, branch: $branch}'
