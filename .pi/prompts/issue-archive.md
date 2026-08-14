---
description: Archive a merged issue's workflow records into the knowledge base, record decisions/lessons, and clean up sandboxes/worktree
argument-hint: "<issue-number>"
---
Archive issue #$1 into the knowledge base. Load the `knowledge-base` skill first; it carries the vault conventions and the git commit snippet. All vault writes use the `obsidian` tool — never bash on vault paths.

Preconditions — verify before touching anything:

- The issue's PR is merged: check `gh pr list --state merged --limit 30` for the `feat/$1-…` branch / issue title. If unclear, ask the user.
- The run dir exists: `$(scripts/issue-workflow/v2/run_dir.sh $1)` (resolve it once at the start and use it throughout).

Steps:

1. Run `scripts/issue-workflow/archive_issue.sh $1`. It copies the raw workflow tree to the vault archive and prints the archive paths as JSON. It makes no curated writes and no commits.
2. Read from the **repo** copies: `issue.md`, `context.md`, `plan.md`, `reviews/summary.md` (if any). Skim `tasks/` and `research/` only where a decision or lesson might be hiding.
3. Write the landing note at the printed `vault_landing_note` path, following the vault's `templates/archive-landing.md` (which now carries a `## Telemetry` section): one-line outcome, what shipped (with PR URL), decisions, rejected approaches, lessons, the **telemetry block** (run `scripts/issue-workflow/v2/telemetry.sh $1` — paste its output verbatim into the `## Telemetry` section; read it BEFORE step 7 deletes the run dir), references (repo paths touched, related topics).
4. **Suggest decision-log and lesson entries — with an explicit recurring-findings check.** Draft each candidate as a concrete note (next free ID, title, 2–3 line body), mining: `context.md`'s decisions-and-rejected-alternatives, chat-made decisions recorded in the artifacts, and the review findings. For review findings specifically: compare this run's findings against archived reviews and `lessons/` (`obsidian search`), and for any finding TYPE that recurs (e.g., the same class of machinery bug flagged again), draft a lesson candidate AND propose the prompt/skill update that would prevent it (role contract in `scripts/issue-workflow/v2/roles/`, a workflow script, or the knowledge-base skill) — the proposal is a deliverable even if the fix itself lands later. Present the drafts as a numbered list; the user approves, edits, or drops each. Write only approved entries, following `templates/decision.md` / `templates/lesson.md`.
5. Topic pages: for each touched topic, create or refresh a thin router — only if it now links ≥2 entries or is clearly recurring. Update `INDEX.md` only if the map itself changed.
6. Commit the vault in **one** atomic commit `kb: archive issue #$1` and push (snippet in the knowledge-base skill). If push fails, commit locally and say so.
7. Clean up the run's infrastructure: run `scripts/issue-workflow/v2/cleanup.sh $1` — it removes the issue's role sandboxes (`issue-$1-*`) and the worktree (`.worktrees/issue-$1` + its branch). Verify with `sbx ls` that zero `issue-$1-*` sandboxes remain. Then remove the local records with `rm -rf <run-dir>` (they live outside the repo; no PR needed). Move the board item to Done: `scripts/issue-workflow/set_status.sh <board_item_id> done` using `board_item_id` from the archived `issue.md` frontmatter.
8. Report: archive paths, landing note (with the telemetry block), decision/lesson IDs created, recurring-findings lesson/proposal outcome, topic updates, vault commit hash, sandboxes removed, board status.

Do not change product code in this phase.
