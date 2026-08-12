---
name: knowledge-base
description: Retrieve and maintain League Tokens project knowledge in the league-tokens Obsidian vault. Use for architecture, domain, ADR, source-sync, or closed-issue archive context.
---

# League Tokens knowledge base

## Retrieval

1. For active specifications or ADRs, read repository `CONTEXT.md` first. The repository remains authoritative for active sources.
2. For vault material, use the `obsidian` tool only, always with `vault="league-tokens"`.
3. Start at `00 Maps/Home.md`, then use Maps, topic pages, properties, and backlinks before a broad vault search.
4. Follow each topic claim to its `50 Sources/` mirror. If mirror provenance differs from the repository source, the repository wins.
5. For closed issue history, search `60 Issue Archive/` by issue number, title, or artifact name. Archived material is vault-canonical only after its manifest records successful verification.

## Preservation

- Do not edit source mirrors without the `30 Engineering/Source Sync Protocol.md` procedure.
- Do not archive or remove workflow files without `30 Engineering/Closed Issue Archival Protocol.md` and a confirmed CLOSED GitHub issue.
- Keep Maps navigational and topics concise; do not duplicate full source documents outside `50 Sources/`.
- Graphify is deferred. Do not install it or scan the vault directly.
