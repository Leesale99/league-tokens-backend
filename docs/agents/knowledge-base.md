# Knowledge base

Project memory lives in the `league-tokens` Obsidian vault (separate GitHub repo: `vault-league-tokens`). The backend repo stays canonical for the current system.

## Boundary rule

If it describes the **current system**, it belongs in the repo. If it is **history, memory, or synthesis**, it belongs in the vault.

| Data | Home |
|---|---|
| `docs/specs/*` (canonical, frozen until MVP) | Repo only |
| `docs/adr/*` | Repo only; a superseded ADR's old state gets a vault decision-log entry before being overwritten |
| `docs/issue-workflows/*` (active issue) | Repo while active → vault archive on close (`/issue-archive <N>`), then deleted locally |
| Decision log — small decisions, rejected alternatives, chat-made decisions | Vault (`decisions/`, IDs `D-NNNN`) |
| Lessons/gotchas — recurring review findings, postmortems | Vault (`lessons/`, IDs `L-NNN`) |
| Topic routers — thin orientation + repo pointers, created lazily | Vault (`topics/`) |
| External research — library/tool evaluations | Vault (`research/`) |
| Runbooks, code docs | Repo — they change with the code |

Never copy repo content into curated vault notes; point with `repo-ref`. Exception: archive folders are history, copied wholesale.

## When agents search the vault

**DO:** past/closed work ("why did we…", "didn't we already try…"); prior art at issue start (`/issue-start`, `/issue-research`); explicit "check the wiki"; synthesis across multiple issues.

**DON'T:** current specs/ADRs/code questions → read the repo (CONTEXT.md → `docs/adr/` → `docs/specs/`). On conflict the repo wins; the agent fixes or flags the wiki note and says so in one line.

Agent access goes through the `knowledge-base` skill (`.pi/skills/knowledge-base/`), which encodes the retrieval and write playbooks.

## Writing and review

- Agents write via the obsidian CLI only (never bash on vault paths), one atomic commit per logical change (`kb: …`), pushed to `origin main` as backup.
- Review = `git log -p` in the vault, the GitHub UI, or Obsidian Git's diff view. Every commit is small and revertable. No branches, PRs, or CI for vault content.
- Note formats are contracts in the vault's `templates/` folder; `INDEX.md` at the vault root is the routing map.
