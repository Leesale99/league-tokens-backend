---
name: knowledge-base
description: Retrieve and maintain League Tokens project knowledge in the league-tokens Obsidian vault. Use for architecture, domain, ADR, source-sync, or closed-issue archive context.
---

# League Tokens knowledge base

## Authority and publication

- Read backend `CONTEXT.md` first for active specifications and ADR context. The backend repository remains authoritative for active sources.
- The separate `Leesale99/vault-league-tokens` repository is the reviewed publication channel for the vault.
- Vault `main` is the published knowledge-base state. A local branch or open PR is draft context and must not be treated as canonical retrieval context.
- Never edit or push vault `main` directly. Use a focused `kb/sync/...`, `kb/archive/...`, or `kb/edit/...` branch and a pull request.

## Retrieval

1. For active specifications or ADRs, read repository `CONTEXT.md` first. The repository remains authoritative for active sources.
2. For vault material, use the `obsidian` tool only, always with `vault="league-tokens"`.
3. Start at `00 Maps/Home.md`, then use Maps, topic pages, properties, and backlinks before a broad vault search.
4. Follow each topic claim to its `50 Sources/` mirror. If mirror provenance differs from the repository source, the repository wins.
5. For closed issue history, search `60 Issue Archive/` by issue number, title, or artifact name. Archived material is vault-canonical only after its manifest records successful verification and its vault PR is merged.

## Source synchronization

- Use `/sync-project-wiki --mode check|plan|apply|verify` and read `30 Engineering/Source Sync Protocol.md` before changing a mirror.
- `check`, `plan`, and `verify` are read-only. `apply` requires explicit authorization and must create a vault branch/PR.
- Use content hashes, not repository HEAD alone, to identify source drift.
- `CONTEXT.md` is initially a trigger-only dependency and does not require a full vault mirror.
- Curated topic pages are interpretations: review them semantically instead of blindly replacing them when a source changes.
- The implementation plan is historical design context, not routine operating context. Read it only when changing the workflow or resolving a contradiction; do not load it for a normal sync or archive.

## Preservation

- Do not edit source mirrors without the `30 Engineering/Source Sync Protocol.md` procedure.
- Do not archive or remove workflow files without `30 Engineering/Closed Issue Archival Protocol.md` and a confirmed CLOSED GitHub issue.
- Archive workflow records through a vault PR first; remove `docs/issue-workflows/<issue>/` only through a separate backend cleanup PR after the vault PR merges and is verified.
- Use Obsidian for every vault content read, create, write, move, rename, and delete. Do not use direct filesystem operations on vault notes.
- Keep Maps navigational and topics concise; do not duplicate full source documents outside `50 Sources/`.
- Graphify is deferred. Do not install it or scan the vault directly.
