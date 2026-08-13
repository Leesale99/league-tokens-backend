---
description: Archive a merged issue's workflow records into the knowledge base, record decisions/lessons, and clean up the repo
argument-hint: "<issue-number>"
---
Archive issue #$1 into the knowledge base. Load the `knowledge-base` skill first; it carries the vault conventions and the git commit snippet. All vault writes use the `obsidian` tool — never bash on vault paths.

Preconditions — verify before touching anything:

- The issue's PR is merged: check `gh pr list --state merged --limit 30` for the `feat/$1-…` branch / issue title. If unclear, ask the user.
- `docs/issue-workflows/$1/` exists.

Steps:

1. Run `scripts/issue-workflow/archive_issue.sh $1`. It copies the raw workflow tree to the vault archive and prints the archive paths as JSON. It makes no curated writes and no commits.
2. Read from the **repo** copies: `issue.md`, `context.md`, `plan.md`, `reviews/summary.md`. Skim `tasks/` and `research/` only where a decision or lesson might be hiding.
3. Write the landing note at the printed `vault_landing_note` path, following the vault's `templates/archive-landing.md`: one-line outcome, what shipped (with PR URL), decisions, rejected approaches, lessons, references (repo paths touched, related topics).
4. **Suggest decision-log and lesson entries.** Draft each candidate as a concrete note (next free ID, title, 2–3 line body), mining: `context.md`'s decisions-and-rejected-alternatives, chat-made decisions recorded in the artifacts, and review findings worth watching for recurrence. Present the drafts as a numbered list; the user approves, edits, or drops each. Write only approved entries, following `templates/decision.md` / `templates/lesson.md`.
5. Topic pages: for each touched topic, create or refresh a thin router — only if it now links ≥2 entries or is clearly recurring. Update `INDEX.md` only if the map itself changed.
6. Commit the vault in **one** atomic commit `kb: archive issue #$1` and push (snippet in the knowledge-base skill). If push fails, commit locally and say so.
7. Clean the repo: remove the local records with `rm -rf docs/issue-workflows/$1/` (they are untracked; no PR needed). Move the board item to Done: `scripts/issue-workflow/move_status.sh <board_item_id> done` using `board_item_id` from the archived `issue.md` frontmatter.
8. Report: archive paths, landing note, decision/lesson IDs created, topic updates, vault commit hash, board status.

Do not change product code in this phase.
