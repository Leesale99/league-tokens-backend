#!/usr/bin/env bash
set -euo pipefail

# Usage: archive_issue.sh <issue-number>
#
# Copies docs/issue-workflows/<issue>/ into the league-tokens vault as the raw
# archive tree archive/<NNNN>-<slug>/ (history, kept wholesale). Performs no
# curated writes and no commits — the /archive-issue prompt then writes the
# landing note, decision/lesson entries, and INDEX updates via the obsidian
# tool, and creates the single atomic vault commit. Also kills the issue's
# leftover context/final-review tmux sessions.
#
# Vault root: $LEAGUE_TOKENS_VAULT or ~/Projects/vaults/league-tokens.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VAULT_ROOT="${LEAGUE_TOKENS_VAULT:-$HOME/Projects/vaults/league-tokens}"

issue_number="${1:?issue number is required}"
src="$REPO_ROOT/docs/issue-workflows/$issue_number"

[[ -d "$src" ]] || { printf 'No workflow dir: %s\n' "$src" >&2; exit 1; }
[[ -d "$VAULT_ROOT" ]] || { printf 'Vault not found: %s (set LEAGUE_TOKENS_VAULT)\n' "$VAULT_ROOT" >&2; exit 1; }

issue_file="$src/issue.md"
[[ -f "$issue_file" ]] || { printf 'Missing issue snapshot: %s\n' "$issue_file" >&2; exit 1; }

title="$(sed -n 's/^# Issue #[0-9][0-9]*: //p' "$issue_file" | head -1)"
[[ -n "$title" ]] || { printf 'Cannot read title from %s\n' "$issue_file" >&2; exit 1; }

slug="$(printf '%s' "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-60)"
[[ -n "$slug" ]] || { printf 'Cannot derive slug from title: %s\n' "$title" >&2; exit 1; }

padded="$(printf '%04d' "$issue_number")"
rel_dir="archive/$padded-$slug"
dest="$VAULT_ROOT/$rel_dir"
[[ ! -e "$dest" ]] || { printf 'Archive already exists: %s\n' "$dest" >&2; exit 1; }
[[ ! -e "$VAULT_ROOT/$rel_dir.md" ]] || { printf 'Landing note already exists: %s\n' "$VAULT_ROOT/$rel_dir.md" >&2; exit 1; }

mkdir -p "$dest"
cp -R "$src"/. "$dest"/

count="$(find "$dest" -type f | wc -l | tr -d ' ')"

# The issue is finished; the orchestrator sessions have no work left to do.
for session in "issue-$issue_number-context" "issue-$issue_number-final-review"; do
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
    printf 'Killed tmux session %s\n' "$session" >&2
  fi
done

jq -n \
  --arg issue "$issue_number" \
  --arg title "$title" \
  --arg slug "$slug" \
  --arg rel_dir "$rel_dir" \
  --arg landing_note "$rel_dir.md" \
  --arg files_copied "$count" \
  '{
    issue: $issue,
    title: $title,
    slug: $slug,
    vault_archive_dir: $rel_dir,
    vault_landing_note: $landing_note,
    files_copied: ($files_copied | tonumber)
  }'
