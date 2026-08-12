---
description: Verify and archive a closed issue workflow into the PR-gated League Tokens Obsidian vault
argument-hint: "<issue-number> --stage <prepare|verify-vault|cleanup> [--state-dir <path>]"
---

Archive closed issue #$1 only after reading `30 Engineering/Closed Issue Archival Protocol.md` in the `league-tokens` vault.

This workflow has two reviewed pull requests. The vault archive PR must merge and be verified before a separate backend cleanup PR may remove the active workflow records. Creating a branch, committing, pushing, or opening either PR is not a deletion authorization.

## Context budget

Read only `CONTEXT.md` once, `30 Engineering/Closed Issue Archival Protocol.md`, and `30 Engineering/Vault PR Workflow.md`. Do not read the PR-gated implementation plan, source-sync protocol, or historical validation reports for a normal archive. Treat workflow artifacts as exact bytes: use inventory, hashes, the Manifest, and Obsidian-side copying rather than loading the entire issue corpus into model context.

## Stage selection

The default stage is `prepare`. Stages are restartable and intentionally do not perform later irreversible actions:

- `prepare` — verify closure, inventory artifacts, create the vault archive branch/notes, validate, and open the vault PR;
- `verify-vault` — require a merged vault PR, verify the archive and Manifest on vault `main`, and record the publication checkpoint;
- `cleanup` — require verified vault publication and explicit user authorization, then create the separate backend cleanup PR.

A stage must stop if the required prior state is absent. The archive landing note and Manifest are the durable state record; local inventory files are ignored implementation state.

## Stage 0 — Closure and repository preflight

1. Confirm the issue is closed:

   ```bash
   gh issue view $1 --json state,url,title,closedAt
   ```

   Stop unless `state` is exactly `CLOSED`. Record the issue URL, title, and `closedAt`.
2. Confirm `docs/issue-workflows/$1/` exists in the backend repository. Stop if absent. Do not archive active work or create a synthetic archive.
3. Read `CONTEXT.md` before interpreting project terminology.
4. Confirm the vault is `league-tokens` and use the `obsidian` tool with `vault="league-tokens"` for every vault content operation.
5. Confirm the vault repository remote is exactly `Leesale99/vault-league-tokens`, the local base is current `origin/main`, and the working tree has no unrelated changes. Create `kb/archive/issue-$1` from vault `main`; never write directly to vault `main`.
6. Inspect the backend workflow directory without modifying it. Preserve unrelated pre-existing backend changes. Do not reset, clean, stash, or commit them.
7. Do not run Graphify.

Report all preflight failures and make no vault writes.

## Stage 1 — Inventory and vault archive branch (`prepare`)

Run this deterministic inventory before loading artifact bodies into model context:

```bash
python3 scripts/knowledge-base/archive_inventory.py --repo . --issue $1 --include-content --output <state-dir>/archive-$1.json --pretty
```

The inventory excludes only `.DS_Store` and records repository-relative path, byte count, SHA-256, media type, source branch, source revision, and artifact count. `--include-content` is for the Obsidian-side adapter; do not print or paste its payload into the conversation.

1. Capture available source branch, implementation PR URL, merge state/commit, issue URL, title, and closure timestamp.
2. On `kb/archive/issue-$1`, create this layout through Obsidian:

   ```text
   60 Issue Archive/YYYY/Issue <number> – <short title>/
     Issue <number> – <short title>.md
     Artifacts/<safe artifact name>.md
     Manifest.md
   ```

   Create parent folders through the Obsidian API. Do not use Bash `cp`, `mv`, `rm`, `cat`, or direct filesystem writes on vault paths.
3. Use `scripts/knowledge-base/archive_adapter.js` from inside `obsidian eval` with the inventory payload. The adapter reads the payload outside model context, verifies every source hash/byte count, and creates the landing note, artifact notes, links, and Manifest through `app.vault`. Pass issue metadata, the vault branch, and `archiveStage: prepared` as adapter options.
4. The adapter must preserve Markdown bodies, render JSON in fenced `json` blocks, and represent non-text artifacts as fenced base64 content. The source hash and byte count remain the authority for exactness.
5. Every artifact note must record original repository path, source byte count, source SHA-256, source issue, and archive verification state.
6. The landing note must include `archive_stage`, `vault_pr`, `vault_merge_commit`, `backend_cleanup_pr`, and `manifest_hash`.
7. The Manifest must include one row per source artifact with source path, vault destination, source bytes, source hash, media type, and verification status, plus publication-state metadata.
8. Link the landing note to every artifact and the Manifest. Link the archive Map only after validation succeeds.

## Stage 2 — Verify before opening the vault PR (`prepare`)

Stop before commit if any check fails:

- source artifact count equals the inventory and Manifest counts;
- every source SHA-256 and byte count matches the inventory;
- every expected destination exists;
- artifact bodies preserve the source content according to the documented rendering rule;
- Manifest rows are unique and complete;
- landing note links to every artifact and Manifest;
- Obsidian unresolved-link check passes or every bounded exception is documented;
- controlled tags and required frontmatter validate;
- changed paths contain only the intended `60 Issue Archive/YYYY/Issue .../` notes and approved navigation/report updates;
- no `.obsidian/`, workspace state, `.DS_Store`, credentials, Graphify output, or unrelated files are staged.

Create a validation report under `99 Reports/` describing the counts, hashes, and results. Do not delete or modify `docs/issue-workflows/$1/`.

## Stage 3 — Vault archive pull request (`prepare`)

Only run this stage after Stage 2 passes.

1. Show the exact changed paths, diff stat, and validation output. Stop on unexpected paths.
2. Commit only the validated vault content:

   ```text
   kb: archive closed issue #$1
   ```
3. Push only `kb/archive/issue-$1` to `Leesale99/vault-league-tokens`.
4. Open a vault PR titled `kb: archive closed issue #$1`.
5. The vault PR body must include:
   - issue URL/title/closedAt;
   - source directory and complete artifact count;
   - Manifest verification results;
   - vault branch and changed paths;
   - validation commands/results;
   - explicit exclusion of `.obsidian/`, `.DS_Store`, Graphify output, and unrelated files;
   - statement that backend workflow records remain untouched until this PR merges.
6. Set `archive_stage: vault-pr-open` and record the vault PR URL/number in the landing note or Manifest through the same focused branch before reporting completion.
7. Do not auto-merge. Report the vault PR URL and wait for review/merge.

An open, approved, or closed-unmerged vault PR is not an archive checkpoint.

## Stage 4 — Verify the merged vault archive (`verify-vault`)

Only run this stage when `--stage verify-vault` is explicit and the user confirms that the vault PR merged:

1. Fetch the vault repository through the approved Git adapter and verify the PR merge commit is on `origin/main`.
2. Read the archive and Manifest through Obsidian on the published `main` state.
3. Recheck artifact counts, SHA-256 values, byte counts, destinations, and links.
4. Record the merged vault PR URL/number and vault merge commit in the landing note through a small follow-up vault PR if the values were not known before the merge.
5. Set `archive_stage: vault-merged`, record `vault_pr`, `vault_merge_commit`, and the verified `manifest_hash` in the landing note/Manifest through a follow-up vault PR if needed.
6. Do not proceed to backend deletion until the merged archive verification is complete and the user explicitly confirms cleanup may be proposed.

## Stage 5 — Separate backend cleanup pull request (`cleanup`)

Only run this stage when `--stage cleanup` is explicit, Stage 4 succeeded, and the user explicitly authorizes cleanup:

1. Create a backend cleanup branch from the relevant backend base. Do not clean or reset unrelated pre-existing changes.
2. Remove exactly `docs/issue-workflows/$1/` and nothing else. Inspect `git diff --name-status` and stop on any other path.
3. Create a separate backend PR whose body links:
   - the GitHub issue;
   - the merged vault archive PR;
   - the vault merge commit;
   - the archive landing note and Manifest;
   - the successful post-merge verification.
4. Do not merge automatically. Report the backend cleanup PR and wait for review.
5. After the cleanup PR merges, verify that exactly the intended workflow directory is gone and that the verified vault archive remains on vault `main`.

If backend cleanup fails or is rejected, retain the verified vault archive and retry through a new focused backend PR. Never mix cleanup with product work.

## Completion report

Report separately:

- selected stage and prior-stage evidence;
- issue closure evidence;
- source inventory and manifest verification;
- vault branch, commit, PR, and merge state;
- backend cleanup branch, commit, PR, and merge state;
- any remaining manual actions;
- archive stage and persisted PR/merge state;
- confirmation that Graphify was not run and unrelated changes were preserved.
