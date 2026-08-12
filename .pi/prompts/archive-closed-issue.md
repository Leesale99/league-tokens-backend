---
description: Verify and archive a closed issue workflow into the League Tokens Obsidian vault
argument-hint: "<issue-number>"
---
Archive closed issue #$1 only after reading `30 Engineering/Closed Issue Archival Protocol.md` in the `league-tokens` vault.

1. Confirm the issue is closed with `gh issue view $1 --json state,url,title,closedAt`. Stop unless `state` is `CLOSED`.
2. Confirm `docs/issue-workflows/$1/` exists. Stop if absent. Do not archive active work or create a synthetic archive.
3. Inventory every substantive source artifact. Exclude only `.DS_Store`. For each file record repository-relative path, byte count, and SHA-256. Obtain current branch and PR/merge information where available.
4. Use the Obsidian tool with `vault="league-tokens"` for every vault operation. Create `60 Issue Archive/YYYY/Issue $1 – short title/`, its landing note, artifact notes, and `Manifest.md`. Preserve every Markdown artifact exactly and render JSON artifacts in fenced `json` blocks. Record original path and SHA-256 on every artifact note.
5. Link the landing note to every artifact. Record GitHub issue/PR references, closure state, branch, merge SHA when available, and the full source-to-vault manifest.
6. Verify source and archive file counts and hashes, confirm every destination exists, and run Obsidian unresolved-link checks on the landing note and its artifacts. Stop on any mismatch.
7. Show the verification result and ask for explicit user confirmation before deleting anything from the repository.
8. Only after confirmation, remove exactly `docs/issue-workflows/$1/`. Do not mix unrelated repository changes into that removal. Update the Issue Archive Map and create a validation report under `99 Reports/`.

Do not run Graphify as part of this workflow.
