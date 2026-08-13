# Issue Workflow v2 — machinery

The v2 workflow runs headless role agents inside Docker Sandboxes (sbx)
microVMs, driven by the interactive host-side conductor. This directory holds
the machinery; role contracts live in `roles/`, track manifests in `tracks/`
(Task 2.2), sandbox templates in `templates/`.

## Prerequisites (host)

- macOS with Docker Desktop **running** (template builds; `docker build` +
  `sbx template load`).
- `sbx` CLI installed and logged in; `pi` authenticated for the model
  provider (`opencode-go`), secrets stored via `sbx secret set-custom`
  (sandboxes see only `sbx-cs-…` placeholders; the host proxy swaps real
  values outbound — never bake keys into images).
- The pi base template loaded: `lt/pi-base:spike` (built by
  `spike/run_spike.sh`; per-role image layers land in Task 4.3).
- Model egress policy: `sbx policy allow network opencode.ai pi.dev`
  (spike runners do this idempotently).

## Role → sandbox spec

Enforced by `dispatch.sh` — never by convention.

| Role | Primary workspace (rw) | Extra mounts (`:ro`) | Network allow-list |
|---|---|---|---|
| `repo-researcher` | `docs/issue-workflows/<N>/research/` | repo | model endpoints only |
| `docs-researcher` | same | repo | model + `context7.com` |
| `web-researcher` | same | repo | model + `api.openai.com` (search provider; adjust if the host configures another) |
| `kb-researcher` | same | repo, vault (`LEAGUE_TOKENS_VAULT` or `~/Projects/vaults/league-tokens`) | model endpoints only |

Notes:

- The primary workspace is the run's `research/` dir mounted rw at its host
  path, shadowing the `:ro` repo mount — agents can write only their own
  `research/<NN>-<slug>/report.md`, never code.
- All roles get the model endpoints (`opencode.ai`, `pi.dev`) — pi needs the
  model. "No network" means *no additional* hosts; egress to anything
  unlisted is blocked (403).
- Sandboxes are long-lived per issue: `issue-<N>-<role>`, created once,
  reused across dispatches, removed at archive (Task 5.2).
- `kb-researcher` also gets the repo `:ro` so the role contract file, cwd,
  and report paths resolve uniformly with the other roles.

## Brief contract

`docs/issue-workflows/<N>/research/<NN>-<slug>/brief.md` — self-contained
per topic: **line 1 is `role: <role>`** (machine-read by `research.sh`), then
the question, scope, expected sources, constraints, and report format.

## Commands

```text
scripts/issue-workflow/v2/research.sh <issue>
    init workflow.json if absent → register briefs as queued agents →
    pre-create one sandbox per role → dispatch ≤4 in parallel →
    phase gated + telemetry totals → summary table.

scripts/issue-workflow/v2/dispatch.sh [--create-only] <issue> <role> <brief-path>
    §4.4 primitive: policy → sandbox create/reuse → pi -p @brief headless
    (event log → agents/<topic>.jsonl) → verdict (reported | failed) →
    workflow.json agent state + telemetry → five-line summary.
```

`pi -p` exits 0 even on model failure, so the verdict comes from the JSONL:
`"stopReason":"error"` → `failed`, no `report.md` → `failed`.

## workflow.json

Per run, `docs/issue-workflows/<N>/workflow.json` (§4.1). Agent states
`queued → running → reported → done` (exceptional `blocked`, `failed`);
phase states `pending → running → gated → done` (`gated` = awaiting human
approval). Concurrent agent-state writes are serialized via
`.workflow.lock`. Telemetry: per-agent `{tokens, wall_seconds}` from the
event log (`message_end.usage.totalTokens`), rolled up per phase.
