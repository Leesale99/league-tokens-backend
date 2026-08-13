---
name: knowledge-base
description: Project memory in the "league-tokens" Obsidian vault — decision log (D-NNNN), lessons/gotchas (L-NNN), closed-issue archive, thin topic routers, external research. Use when a question concerns PAST or CLOSED work ("why did we…", "what happened with…", "didn't we already try…", "what keeps going wrong in reviews"), when gathering prior art for a new issue (/issue-start, /issue-research), when the user says "check the wiki", when recording a decision or lesson, or when archiving a closed issue (/issue-archive). Do NOT use for current specs, ADRs, or code — the repo is canonical (CONTEXT.md → docs/adr/ → docs/specs/). On any conflict the repo wins; then fix or flag the wiki note and say so in one line.
---

# Knowledge Base

The `league-tokens` Obsidian vault is the project's memory. Separate git repo (`vault-league-tokens` on GitHub), pushed to `origin main` as backup.

**All vault operations use the `obsidian` tool** (pass `vault="league-tokens"` if ambiguous). Never use bash on vault paths — it bypasses Obsidian's index.

## Boundary rule

Current system → repo. History, memory, synthesis → vault. Never copy repo content into curated notes; point with `repo-ref`. Exception: issue archive folders are history, copied wholesale by `/issue-archive`.

## Retrieval playbook — minimal context

1. Read `INDEX.md` (vault root). It is the routing map: sections, ID schemes, conventions.
2. `obsidian search query="…"` or go straight to a section: `decisions/`, `lessons/`, `topics/`, `archive/`, `research/`.
3. Read the **one** most relevant note. Follow `[[links]]` / `backlinks` only when the answer needs it.
4. Answer and cite vault paths. If wiki and repo disagree: repo wins — fix or flag the wiki note and report it in one line.

What the vault answers: what issue #N did/decided/shipped (archive landing note) · approaches rejected for X and why (landing notes + decisions) · recurring review failures (lessons) · small decisions without an ADR (decision log) · what topics exist (INDEX). It never answers current-state questions — a topic page only orients and points to the repo.

## Write playbook

1. Read the matching `templates/` note first — it is the format contract.
2. Conventions: lowercase-hyphen filenames; frontmatter `type` / `status` / `updated` plus type fields; quote `#`-prefixed tags in YAML (`- "#type/decision"`); one-line summary under the title.
3. IDs: decisions `D-NNNN`, lessons `L-NNN`. Scan the folder, take the next number.
4. Topic pages are routers (≤10 lines), never summaries. Create lazily: a topic earns a page when it has ≥2 linked entries or an agent needed it and it didn't exist.
5. Update `INDEX.md` only when the map itself changes.
6. Issue archival goes through `/issue-archive` — never hand-archive.

## Commit after every logical change

One atomic commit per logical change (`kb: archive issue #5`, `kb: decision D-0007 …`), then push. Run via the obsidian tool:

```
obsidian run="eval code='
const {execSync} = require(\"child_process\");
const p = app.vault.adapter.getBasePath();
execSync(\"git add -A\", {cwd: p});
execSync(\"git commit -m \\\"kb: <message>\\\"\", {cwd: p});
execSync(\"git push origin main\", {cwd: p});
'"
```

If push fails (offline, remote ahead), still commit locally and tell the user.

## Review flow for the human

`git log -p` in the vault, the GitHub UI, or Obsidian Git's diff view. Every commit is small and revertable. No branches, no PRs, no CI for vault content.
