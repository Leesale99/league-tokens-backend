---
description: Verify and archive a closed issue workflow into the PR-gated League Tokens Obsidian vault
argument-hint: "<issue-number>"
---

Archive closed issue #$1 only after reading `30 Engineering/Closed Issue Archival Protocol.md` in the `league-tokens` vault.

This workflow has two reviewed pull requests. The vault archive PR must merge and be verified before a separate backend cleanup PR may remove the active workflow records. Creating a branch, committing, pushing, or opening either PR is not a deletion authorization.

## Context budget

Read only `CONTEXT.md` once, `30 Engineering/Closed Issue Archival Protocol.md`, and `30 Engineering/Vault PR Workflow.md`. Do not read the PR-gated implementation plan, source-sync protocol, or historical validation reports for a normal archive. Treat workflow artifacts as exact bytes: use inventory, hashes, the Manifest, and Obsidian-side copying rather than loading the entire issue corpus into model context.

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

## Stage 1 — Inventory and vault archive branch

1. Inventory every substantive file under `docs/issue-workflows/$1/`. Exclude only `.DS_Store`; do not silently exclude logs, JSON, Markdown, reports, or status files. Record for each source:
   - repository-relative path;
   - byte count;
   - SHA-256;
   - content type.
2. Capture available source branch, implementation PR URL, merge state/commit, issue URL, title, and closure timestamp.
3. On `kb/archive/issue-$1`, create this layout through Obsidian:

   ```text
   60 Issue Archive/YYYY/Issue <number> – <short title>/
     Issue <number> – <short title>.md
     Artifacts/<safe artifact name>.md
     Manifest.md
   ```

   Create parent folders through the Obsidian API. Do not use Bash `cp`, `mv`, `rm`, `cat`, or direct filesystem writes on vault paths.
4. Preserve each Markdown artifact exactly in its artifact note body after the archive note's provenance frontmatter. Render JSON artifacts in a fenced `json` block while preserving the exact serialized content. For other file types, use an appropriate fenced block and state the original media/type.
5. Every artifact note must record original repository path, source byte count, source SHA-256, source issue, and archive verification state.
6. Create a landing note with issue state, URL, title, `closedAt`, source branch/PR/merge information, vault branch, and placeholders for the vault PR and later backend cleanup PR.
7. Create `Manifest.md` with one row per source artifact mapping source path to vault destination, source bytes, source hash, destination bytes (where applicable), and verification status.
8. Link the landing note to every artifact and the Manifest. Link the archive Map only after validation succeeds.

## Stage 2 — Verify before opening the vault PR

Stop before commit if any check fails:

- source artifact count equals Manifest count;
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

## Stage 3 — Vault archive pull request

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
6. Do not auto-merge. Report the vault PR URL and wait for review/merge.

An open, approved, or closed-unmerged vault PR is not an archive checkpoint.

## Stage 4 — Verify the merged vault archive

After the user confirms that the vault PR merged:

1. Fetch the vault repository through the approved Git adapter and verify the PR merge commit is on `origin/main`.
2. Read the archive and Manifest through Obsidian on the published `main` state.
3. Recheck artifact counts, SHA-256 values, byte counts, destinations, and links.
4. Record the merged vault PR URL/number and vault merge commit in the landing note through a small follow-up vault PR if the values were not known before the merge.
5. Do not proceed to backend deletion until the merged archive verification is complete and the user explicitly confirms cleanup may be proposed.

## Stage 5 — Separate backend cleanup pull request

Only after Stage 4 succeeds and the user explicitly authorizes cleanup:

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

- issue closure evidence;
- source inventory and manifest verification;
- vault branch, commit, PR, and merge state;
- backend cleanup branch, commit, PR, and merge state;
- any remaining manual actions;
- confirmation that Graphify was not run and unrelated changes were preserved.
