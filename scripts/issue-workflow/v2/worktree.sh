#!/usr/bin/env bash
# Usage: worktree.sh <issue> <slug>  — create (or reuse) the issue's worktree
#        worktree.sh <issue> remove  — remove the worktree and its branch
#
# Phase 3 Task 3.1 — the implementation worktree. The conductor runs this from
# the main checkout; the task-implementer sandbox mounts .worktrees/issue-<N>
# read-write (plus <repo>/.git for objects and per-worktree state) and commits
# there. The main checkout's working tree is never mounted into the sandbox.
# The worktree branch follows the repo convention feat/<issue>-<slug> (same
# rule open_pr.sh enforces), so the PR can be opened from the host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config.json"
issue="${1:?issue number is required}"
action="${2:-}"
repo_root="$(git rev-parse --show-toplevel)"
wt="$repo_root/.worktrees/issue-$issue"
prefix="$(jq -r '.branch.prefix' "$CONFIG")"

die() { printf 'worktree: %s\n' "$*" >&2; exit 1; }

if [[ "$action" == "remove" ]]; then
  if [[ -d "$wt" ]]; then
    branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
    git worktree remove --force "$wt"
    printf 'worktree: removed %s\n' "${wt#"$repo_root"/}" >&2
    if [[ "$branch" != "HEAD" ]] && git show-ref --verify --quiet "refs/heads/$branch"; then
      git branch -D "$branch"
      printf 'worktree: deleted branch %s\n' "$branch" >&2
    fi
  else
    printf 'worktree: nothing to remove (%s)\n' "${wt#"$repo_root"/}" >&2
  fi
  exit 0
fi

slug="$action"
[[ -z "$slug" ]] && die "usage: worktree.sh <issue> <slug> | <issue> remove"
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug '$slug' must match ^[a-z0-9][a-z0-9-]*$"
[[ ${#slug} -le 40 ]] || die "slug too long (${#slug} > 40 chars)"
branch="$prefix/$issue-$slug"

if [[ -d "$wt" ]]; then
  current="$(git -C "$wt" rev-parse --abbrev-ref HEAD)"
  [[ "$current" == "$branch" ]] || die "worktree exists on '$current' — expected '$branch'; pass the matching slug"
  printf 'worktree: reusing %s (branch %s)\n' "${wt#"$repo_root"/}" "$branch" >&2
else
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$wt" "$branch" >/dev/null
  else
    git worktree add -b "$branch" "$wt" >/dev/null
  fi
  printf 'worktree: created %s (branch %s)\n' "${wt#"$repo_root"/}" "$branch" >&2
fi
printf '%s\n' "$wt"
