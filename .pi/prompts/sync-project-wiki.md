---
description: Synchronize League Tokens repository sources into the PR-gated Obsidian knowledge base
argument-hint: "--mode <check|plan|apply|verify> [--source-ref <committed-ref>]"
---

Synchronize the League Tokens project knowledge base without bypassing repository authority or vault review.

## Required safety rules

- Read `CONTEXT.md` before inspecting source details.
- Use the `league-tokens` Obsidian vault only through the `obsidian` tool with `vault="league-tokens"`. Never use Bash `cat`, `cp`, `mv`, `rm`, `sed`, `find`, or direct filesystem writes for vault content.
- The backend repository is canonical for active `CONTEXT.md`, `specs/*.md`, and `docs/adr/*.md` sources. The vault contains projections.
- Never write directly to vault `main`, never force-push, and never auto-merge a vault pull request.
- Preserve unrelated pre-existing backend changes. Do not reset, clean, stash, or commit them.
- Do not install or run Graphify.
- Do not delete source mirrors automatically. A removed or renamed source requires an explicit mapping or an `archived`/`superseded` decision.
- CI and this workflow must not commit or push on the user's behalf without the explicit `apply` mode and confirmation.

## Modes and argument handling

Parse the requested mode from the command arguments. If no mode is supplied, use `check` and do not modify either repository.

- `--mode check`: read-only source inventory and mirror drift report.
- `--mode plan`: read-only proposed changes, mirror destinations, and affected topic pages.
- `--mode apply`: explicit, branch-local synchronization followed by validation, commit, push, and PR preparation. Ask for confirmation immediately before the first vault write if the user did not already explicitly authorize apply.
- `--mode verify`: validate a selected branch or merged PR against the selected committed backend source ref; make no content changes.

Accept `--source-ref <ref>` for a committed backend ref. Default to the current backend `HEAD` only after confirming that the source tree is committed. `check` and `plan` may inspect a draft ref only when the user explicitly labels it draft; a draft-based vault PR must not be merged before the backend source decision merges.

## Repository locations

- Backend: current working repository, expected remote `git@github.com:Leesale99/league-tokens-backend.git`.
- Vault: `/Users/aleksrdvn/Projects/vaults/league-tokens`, expected remote `git@github.com:Leesale99/vault-league-tokens.git`, Obsidian vault name `league-tokens`.
- Source inventory helper: `scripts/knowledge-base/source_inventory.py`.

Do not assume these paths are correct. Verify remotes before apply or verify. If a path or remote differs, stop and report it.

## Phase 0 — Preflight for every mode

1. Read `CONTEXT.md`.
2. Read only the mode-relevant operating note:
   - `check` or `plan`: `30 Engineering/Source Sync Protocol`;
   - `apply`: `30 Engineering/Source Sync Protocol` and `30 Engineering/Vault PR Workflow`;
   - `verify`: `30 Engineering/Vault PR Workflow` plus the repository validator output.

   Do not read the implementation plan, closed-issue protocol, or historical validation report for a normal source sync. Read the plan only when changing this workflow or resolving a contradiction in the operating notes.
3. Run `obsidian vault` with `vault="league-tokens"`; confirm the vault name and root.
4. Verify both Git remotes exactly. For vault VCS operations use the approved Obsidian Git/guarded adapter; use Obsidian for note content.
5. Confirm the vault starts from current `origin/main`. It must be on `main` for preflight; a dirty tree is a hard stop unless the user explicitly identifies every intended change as part of the current operation.
6. Confirm the backend source ref resolves to a commit. If no explicit `--source-ref` is supplied, a dirty backend tree is a hard stop. With an explicit committed ref, unrelated backend work may remain dirty only if `git diff --name-only -- CONTEXT.md specs docs/adr` is empty; report the unrelated paths and never stage them. Never sync uncommitted source content as canonical.
7. Inspect `.obsidian/plugins/obsidian-git/data.json` through Obsidian. Automatic commit/save, push, pull, and pull-on-boot timers must be disabled (`autoSaveInterval: 0`, `autoPushInterval: 0`, `autoPullInterval: 0`, `autoPullOnBoot: false`). These local settings are not staged.
8. Check the current vault branch and changed paths. Stop if `.obsidian/`, workspace files, `.DS_Store`, Graphify output, or unrelated paths would be included.

Report all preflight failures together and make no vault writes.

## Phase 1 — Source inventory

Run the pure repository helper for the selected committed ref:

```bash
python3 scripts/knowledge-base/source_inventory.py \
  --repo . --source-ref <ref> --pretty
```

For an apply without an explicit source ref, add `--require-clean`. For an explicit committed ref, separately confirm that no `CONTEXT.md`, `specs/`, or `docs/adr/` path is dirty; unrelated dirty paths must remain untouched.

The source inventory includes:

- `CONTEXT.md` as a trigger/dependency with no required full mirror;
- every `specs/*.md` file;
- every `docs/adr/*.md` file;
- source path, source type, source ref, resolved revision, last source-changing revision, SHA-256, byte count, and expected mirror path.

Use content hashes as drift identity. A changed repository HEAD with unchanged source content is not source drift.

## Phase 2 — Mirror comparison

Use Obsidian to read every Markdown file under `50 Sources/`. Parse source mirror frontmatter and compare:

```yaml
source_path: relative/backend/path.md
source_revision: committed backend revision
source_hash: sha256
source_byte_count: integer
synced_at: ISO-8601 timestamp
source_type: specification|glossary|adr
```

Classify each inventory item as `current`, `changed`, `missing mirror`, `unexpected mirror`, `renamed/deleted candidate`, or `uncommitted source`.

- `CONTEXT.md` is `trigger-only` unless the user explicitly approves adding a full mirror.
- Match existing mirrors by `source_path`, not only by filename.
- Detect duplicate `source_path` values.
- For a changed source, preserve the mirror's provenance and navigation sections while replacing only the source-content projection.
- For a new source, choose a stable destination under the appropriate `50 Sources/` directory and record the mapping in the report.
- For a renamed/deleted source, stop and ask for an explicit mapping or archival status.

In `check` mode, print the inventory and stop. In `plan` mode, print the proposed vault paths, old/new hashes, affected Maps/topics, and expected changed paths, then stop. Neither mode may create a branch or write notes.

## Phase 3 — Apply on a vault branch

Only for `apply` after preflight and comparison succeed:

1. Ensure vault local `main` is current with `origin/main` through the approved Git adapter.
2. Create `kb/sync/backend-<short-source-sha>` from that exact `main`. Use a unique suffix if the branch already exists; never reuse a branch containing unrelated changes.
3. Confirm the branch is checked out before any note write.
4. Through Obsidian only:
   - update changed source mirrors;
   - add missing mirrors;
   - add/refresh `source_byte_count` without changing a source hash checkpoint unnecessarily;
   - preserve `source_path`, `source_revision`, `source_hash`, `synced_at`, and `source_type` provenance;
   - update Maps only if the source inventory changes;
   - inspect and list affected curated topic pages;
   - update curated prose only after semantic review and link it to the authoritative mirror;
   - create `99 Reports/Source Sync <timestamp or short sha>.md`.
5. The report must include backend repository, source ref, source revision, source inventory, old/new hashes, mirror paths, affected topics, validation results, branch, PR status, and whether the source was merged or draft.

Do not write to a vault file outside the approved scope. Do not create a backend sync receipt in this workflow.

## Phase 4 — Validate before publication

Run both repository and Obsidian checks. Stop before commit if any required check fails:

- the source inventory succeeds for the selected committed ref; when no explicit ref was supplied, `--require-clean` also succeeds;
- no canonical source path (`CONTEXT.md`, `specs/`, or `docs/adr/`) is dirty;
- all required mirrors exist and their hashes/byte counts match the selected ref;
- no duplicate `source_path` values;
- required source metadata is present and valid;
- controlled `type/` and `domain/` tags are valid;
- unresolved links are zero or an explicit bounded exception is recorded;
- Maps and Base files parse;
- every source mirror has navigation/backlinks;
- affected topic pages link to authority;
- changed paths are limited to the intended vault scope;
- no `.obsidian/`, `.DS_Store`, Graphify output, credentials, or unrelated files are staged.

For `verify`, run these checks against the selected branch or merged `origin/main` and report pass/fail without modifying notes.

## Phase 5 — Commit, push, and open the vault PR

Do not perform this phase for `check`, `plan`, or `verify`.

1. Show the exact `git diff --stat`, `git diff --name-status`, and staged path list. Stop if anything is unexpected.
2. Stage only intended vault content and approved validation workflow files. Never stage `.obsidian/`.
3. Create one focused commit:

```text
kb: sync league-tokens to backend <short-source-sha>
```

4. Push only the branch to `Leesale99/vault-league-tokens`.
5. Open a non-draft PR unless the user asks for a draft. Suggested title:

```text
kb: sync project wiki to backend <short-source-sha>
```

The PR body must include:

- backend repository and committed source ref;
- source files and old/new hashes;
- vault files changed;
- affected topic pages;
- validation commands and results;
- explicit exclusion of `.obsidian/`, workspace state, `.DS_Store`, Graphify output, and unrelated files;
- link to the backend source PR or commit;
- whether content came from merged or draft backend work;
- a reminder that merge, not branch creation, publishes the vault.

Never auto-merge. Report the branch, commit, PR URL, validation results, and any repository-protection limitation.

## Post-merge verification

Only after the user or reviewer merges the vault PR:

1. fetch through the approved Git adapter;
2. verify the merge commit and expected paths on `origin/main`;
3. read the published source mirrors through Obsidian and recalculate hashes against the merged backend source ref;
4. update the sync report with the merged vault PR and commit only through a follow-up vault PR if that metadata was not known before merge;
5. return the local vault to `main` unless the user requests otherwise.

An open, approved, or closed-unmerged PR is not canonical.

## Failure handling

- Preflight or validation failure: no commit, push, or vault PR.
- Unexpected path: stop and show the path.
- Source rename/delete: retain the old mirror and request an explicit mapping.
- Vault PR rejection: revise or recreate the branch from `main`; do not rewrite published history.
- Post-merge mistake: create a corrective vault PR.
- Never clean or reset unrelated backend changes.

At completion, report the mode, source ref, classifications, changed paths, validation results, branch/commit/PR if any, and remaining manual actions. Clearly distinguish draft branch state from merged `main` state.
