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
| `repo-researcher` | `<run>/research/` | repo `:ro` | model endpoints only |
| `docs-researcher` | same | repo | model + `context7.com` |
| `web-researcher` | same | repo | model + `api.openai.com` (search provider; adjust if the host configures another) |
| `kb-researcher` | same | repo, vault (`LEAGUE_TOKENS_VAULT` or `~/Projects/vaults/league-tokens`) | model endpoints only |
| `context-synthesizer` | `<run>` | repo `:ro` | model endpoints only |
| `plan-critic` | same | repo `:ro` | model endpoints only |
| `reviewer-correctness` | `<run>` (writes `reviews/correctness.md`) | repo `:ro` | model endpoints only |
| `reviewer-quality` | same | repo `:ro` | model endpoints only |
| `reviewer-quality-depth` | same | repo `:ro` | model endpoints only |
| `reviewer-security` | same | repo `:ro` | model endpoints only |
| `reviewer-requirements` | same | repo `:ro` | model endpoints only |
| `task-implementer` | `.worktrees/issue-<N>` rw | run dir `:ro`, `.git` rw | model endpoints + Go module proxy (`proxy.golang.org`, `sum.golang.org` — the repo has no `vendor/`) |
| `task-reviewer` | same | same | same |

Each role also declares its expected **report path**: research roles write
`research/<NN>-<slug>/report.md`; the synthesizer writes `context.md`; the
plan-critic writes `plan-critic.md` — all at the absolute paths the
dispatch message names (the run dir lives OUTSIDE the repo, resolved by
`v2/run_dir.sh <N>` → `~/Projects/league-tokens/issue-workflows/<N>`; the
conductor's sandbox mounts it rw alongside the repo). The five reviewer
roles (Phase 4) write `reviews/<focus>.md` and their reports carry a
machine-read `reviewed_head:` frontmatter line (Task 4.2's incremental
re-review base). Task roles write
`reports/<task>.implement.md` / `reports/<task>.review.md` **inside the
worktree** (the worktree's `docs/issue-workflows/<N>/` is git-ignored, so
reports can never enter a commit).

Task roles execute with cwd = the worktree (other roles: repo root). Task
state lives in `workflow.json` as objects — `.phases.implement.tasks[<file>]
= {state: running|done, commit: <sha>}`; the reviewer's `verdict: green|red`
line (line 1 of the review report) drives the conductor's fix loop
(amend-brief → re-dispatch, max 3 rounds).
The verdict (`reported | failed`) checks that path after the run.

- The primary workspace is the run's `research/` dir (or the run dir for
  the synthesizer) mounted rw at its host path — agents can write only
  their own artifact, never code. The repo root is mounted `:ro`
  wholesale — valid because the run dir lives OUTSIDE the repo (the
  relocation: sbx/virtiofs gives EROFS on a rw workspace nested inside a
  `:ro` mount, host acceptance Phase 1; the pre-relocation per-entry
  `:ro` enumeration + `_repo/` file mirror were its workaround and are
  gone). Task roles get NO repo mount (their worktree primary contains
  every tracked file) plus `.git` rw and the run dir `:ro` via `extras`.
- All roles get the model endpoints (`opencode.ai`, `pi.dev`) — pi needs the
  model. "No network" means *no additional* hosts; egress to anything
  unlisted is blocked (403).
- Sandboxes are long-lived per issue: `issue-<N>-<role>`, created once,
  reused across dispatches, removed at archive (Task 5.2).
- `kb-researcher` also gets the vault `:ro` (its only extra mount).

## Brief contract

`<run>/research/<NN>-<slug>/brief.md` (`<run>` = `v2/run_dir.sh <N>`) — self-contained
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

scripts/issue-workflow/v2/review.sh <issue> [--redispatch]
    final review (Phase 4): refuses Track S (parallelism.review: 0 — CI
    is the only gate), guards worktree + implemented tasks, registers the
    five focuses (manifest agents.review) as queued agents, pre-creates
    the sandboxes, dispatches ≤5 in parallel — each reviewer loading its
    golang-* skills via --skill (/opt/cc-skills-golang, baked in the
    image) — then phase gated + telemetry.review + summary table.
    Reports: reviews/<focus>.md.
```

`pi -p` exits 0 even on model failure, so the verdict comes from the JSONL:
`"stopReason":"error"` → `failed`, no report at the role's report path →
`failed`. Phase-level dispatches (e.g. the synthesizer) take a brief at the
run root (`synthesis-brief.md`) instead of a research topic dir.

## research.sh modes

```text
research.sh <issue>              dispatch the queued backlog (≤4 parallel)
research.sh <issue> --redispatch flip failed agents back to queued after the
                                 human amended their briefs, then re-dispatch
research.sh <issue> --finalize   mark research done after the human approved
                                 context.md → next: /issue-plan
```

## workflow.json

Per run, `<run>/workflow.json` (§4.1; `<run>` = `v2/run_dir.sh <N>`, outside the repo). Agent states
`queued → running → reported → done` (exceptional `blocked`, `failed`);
phase states `pending → running → gated → done` (`gated` = awaiting human
approval). Concurrent agent-state writes are serialized via
the portable mkdir lock `.workflow.lockd` (owner-PID file; the owner
releases it on exit, a dead owner's lock is stolen after >120 s).
Telemetry: per-agent `{tokens, wall_seconds}` from the
event log (`message_end.usage.totalTokens`), rolled up per phase.

## Conductor state machine (Task 2.1)

```text
scripts/issue-workflow/v2/next.sh <issue>
    resolve the run's state → prints `next: <command>` (exit 0) or
    `blocked: <reason>` (exit 1). Mechanical; /issue-next executes the
    printed phase command and presents its gates.

scripts/issue-workflow/v2/mark.sh <issue> <plan-done|task-done <task-file>|pr-done>
    record phase completions after their gates (keeps jq out of prompts).
```

Phase order: research → plan → implement → review → pr → archive. Research
state is authoritative from `research.sh`; plan/task/pr completions are
recorded via `mark.sh`; the review gate is probed with
`check_review_gate.sh`. Track manifests (Task 2.2) will select phases per
track.

## Tracks (Task 2.2)

Manifests in `tracks/<S|M|L>.md` declare, machine-readably (flat
`key: value` frontmatter), the phases to run, parallelism budgets, agents
per phase, required artifacts, and gates:

| Track | Phases | Notes |
|---|---|---|
| S | plan,implement,pr | brief-only plan (one task brief from `issue.md`); no research; **no local review — CI is the only gate** |
| M | research,plan,implement,review,pr | full pipeline, 3 gates |
| L | research,plan,implement,review,pr | M + spike option + `plan-critic` pass (Task 2.3) + stacked-PR option |

- `/issue-start` proposes the track from signals; the human confirms; `mark.sh
  <N> track <S|M|L> "<reason>"` records it in `track_history` (creates
  `workflow.json` at intake; mid-flight changes append a history entry).
- `next.sh` and `research.sh` read the manifest (`phases`, `parallelism.research`);
  adding a step = editing a manifest.

## Reviewability budgets (Task 2.4)

- One task ≈ one commit ≲ **300 LOC** of diff; the issue ≈ one PR ≲
  **800 LOC**. `/issue-plan` self-flags violations with a concrete split
  proposal (more tasks; stacked PRs for Track L) — never a silently
  oversized plan. `plan-critic` checks the same budgets (Task 2.3).
- Task briefs open with a **TL;DR for humans** and must contain all six
  required sections (TL;DR, Description, Context, Acceptance criteria,
  Implementation and verification guidance, References).

## Implementation worktree (Task 3.1)

`worktree.sh <N> <slug>` creates (or reuses) `.worktrees/issue-<N>` on
`feat/<N>-<slug>` (branch rule shared with `open_pr.sh`); `<N> remove`
removes the worktree and its branch. The conductor runs it from the main
checkout before dispatching implementation.

Implementer sandbox mounts (`dispatch.sh` role spec — enforced there):

| Path | Perms | Why |
|---|---|---|
| `.worktrees/issue-<N>` | rw (primary) | the implementation worktree — the only rw working files |
| `<repo>/.git` | rw | git objects + per-worktree HEAD/index for commits |
| `<run>` (`issue-workflows/<N>`) | ro | briefs/plan/context (live host copy, outside the repo) |

The main checkout is **never mounted**; `github.com` is not in the network
allow-list, and no credentials exist in the sandbox, so a push fails by
policy. The base image bakes the project git identity + `safe.directory '*'`
(commit authorship from inside sandboxes) — rebuild + `sbx template load`
after changing `templates/base.Dockerfile` (`spike/run_worktree_test.sh` does
both). The `task-implementer`/`task-reviewer` contract files live in
`v2/roles/`; their sandboxes + mounts are live (Tasks 3.1/3.2).
