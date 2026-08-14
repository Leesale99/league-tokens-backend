# Issue Workflow v2 — Implementation Plan

**Status:** approved design, ready for implementation
**Decision record:** [Issue Workflow v2 — Design](issue-workflow-v2-design.md) — read it first
**Audience:** the agent implementing this (separate session) and the human reviewing its work

> **Handoff note.** This plan is the contract. Implement it phase by phase, in order.
> Each phase ends in a working, usable state — do not start the next phase until the
> current one's acceptance criteria pass. Follow repo conventions: CONTEXT.md →
> the design doc → this plan. If a spike outcome (Phase 0) contradicts a design assumption,
> stop and report rather than improvising around it.

## 1. Goals and non-goals

Goals (from the design session — see the design doc's Context section):

1. Small, human-reviewable PRs — enforced by reviewability budgets, not exhortation.
2. Decisions grounded in fresh multi-source research: repo, context7, web, vault.
3. Teamwork: human-approved research backlog and plan before any implementation.
4. Educational: every artifact carries a human-readable narrative of decisions,
   alternatives, and rationale.
5. Subagents with bounded blast radius: one job, scoped tools/skills/network/creds.
6. Sequential main workflow; parallelism only for research and final review.
7. Simple now, extensible later: track manifests as the extension mechanism.

Non-goals (for this plan):

- Rewriting the artifact chain or the GitHub-board conventions (they stay).
- An external orchestrator service or new runtime dependencies beyond sbx + pi.
- Changing the CI pipeline (parity with it is a constraint, not a target).
- Parallel implementation of tasks (sequential by design; revisit later).

## 2. Locked decisions (do not relitigate)

| # | Decision | Rationale |
|---|---|---|
| D1 | `plan-critic` is a real separate role, not a planner self-pass | Fresh eyes find holes the planner is blind to |
| D2 | `kb-researcher` reads the vault via a **raw read-only mount** inside the sandbox | Simplest thing that works; obsidian CLI stays host-side |
| D3 | Track S has **no local final review**; CI is the only review gate | Honest about "trivial"; avoids ceremony theater |
| D4 | Per-phase **token/time telemetry** in `workflow.json` from day one | Data needed to tune tracks/parallelism later |
| D5 | Evolve current workflow; keep artifact chain + 3 human gates | The skeleton already embodies "pay at the beginning" |
| D6 | Headless subagents in sbx (`sbx create` + `sbx exec … pi -p`); interactive conductor only | Real isolation; no mid-flight steering; `sbx exec -it` escape hatch |
| D7 | `task-implementer` works in a mounted **git worktree**, never pushes; no sandbox holds GitHub write creds | Credentials stay on host; review/PR tooling stays on host |
| D8 | Specialization along capability boundaries (~12 roles), not one agent per micro-job | Cold-start cost and handoff context loss |
| D9 | Authority hierarchy: repo/ADRs > context7 > vault > web (non-authoritative) | Contradictions are surfaced, never silently resolved |
| D10 | Tracks S/M/L; conductor proposes, human confirms; mid-flight changes recorded | Sizing discussion is a teaching moment |

## 3. Current-state inventory

Reuse as-is (with Phase 0 fixes): `capture_issue.sh`, `create_branch.sh`,
`move_status.sh`, `open_pr.sh`, `add_label.sh`, `remove_label.sh`,
`archive_issue.sh`, `config.json`, the artifact directory layout
`docs/issue-workflows/<N>/`, prompt templates `/start-issue`, `/plan-issue`,
`/implement-task`, `/review-task`, `/open-pr`, `/archive-issue`, the five
`/review-*` rubric prompts, and both approval gates. (All renamed per §5 in
Task 0.5.)

Replace: `context/ORCHESTRATOR.md` and `final-review/ORCHESTRATOR.md` (their brains
move into the conductor + small role prompts), `dispatch-worker.sh`,
`dispatch-reviewer.sh`, `start-session.sh` ×2 (tmux session machinery).

Retire at the end (Phase 5): `context/close-worker.sh`, `context/status.sh`, tmux
docs in `scripts/issue-workflow/README.md`.

Known defects to fix in Phase 0 (from the 2026-08-13 workflow review):

- `query_ready.sh <N>` numbered path never checks board status; `/open-pr` relies on
  that same call for an In-progress item — split into a status-agnostic lookup
  plus an explicit Ready assertion at issue start (renamed in Task 0.5).
- `open_pr.sh` never checks the current branch matches `feat/<issue>-*` — a wrong
  branch produces a PR saying `Closes #<wrong-issue>`.
- `docs/issue-workflows/` is not git-ignored — accidental `git add -A` commits
  workflow records.
- tmux sessions are never killed after `/open-pr` and `/archive-issue`.
- `reviews/summary.md` has no machine-checkable gate for `/open-pr`.
- Local `/review-*` prompts reference `golang-*` skills that are only installed in
  CI; `/.agents` comment in `.gitignore` is stale.
- `config.json`'s `labels` block is dead config; `ready-for-human` is applied at
  open-pr with a meaning ("in human review") that clashes with its triage meaning
  ("requires human implementation").

## 4. Target architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Human + conductor (interactive pi, host, holds credentials) │
│  state machine · dispatch · gate summaries · board ops      │
└──────────┬──────────────────────────────────────────────────┘
           │ sbx create per role/issue · sbx exec <name> pi -p @brief …
           ▼
 research (≤4 parallel, :ro)        implementation (sequential)
  · repo-researcher  no network      · task-implementer  worktree rw
  · docs-researcher  context7 net    · task-reviewer     repo ro + git
  · web-researcher   search net   final review (≤5 parallel, :ro)
  · kb-researcher    vault :ro        · reviewer-correctness
 planning (sequential)                · reviewer-quality
  · context-synthesizer               · reviewer-quality-depth
  · planner · plan-critic (Track L)   · reviewer-security
                                      · reviewer-requirements
           ▼
 artifacts: docs/issue-workflows/<N>/ + workflow.json
 gates: research backlog → plan → PR
```

### 4.1 `workflow.json` schema (per issue, at `docs/issue-workflows/<N>/workflow.json`)

```json
{
  "issue": 46,
  "track": "M",
  "track_history": [{ "from": null, "to": "M", "at": "…", "reason": "intake" }],
  "phase": "research",
  "phases": {
    "research": {
      "state": "running",
      "agents": {
        "01-map-ledger-seams": {
          "role": "repo-researcher",
          "state": "done",
          "sandbox": "issue-46-repo-researcher",
          "report": "research/01-map-ledger-seams/report.md"
        }
      }
    },
    "plan": { "state": "pending" },
    "implement": { "state": "pending", "tasks": { "01-….md": "pending" } },
    "review": { "state": "pending", "reviewed_head": {} },
    "pr": { "state": "pending" }
  },
  "telemetry": {
    "research": { "tokens": 0, "wall_seconds": 0, "dispatches": 0 }
  }
}
```

Agent states: `queued → running → reported → done` (exceptional `blocked`,
`failed`). Phase states: `pending → running → gated → done` (`gated` = awaiting
human approval). See §5 for the full naming and state vocabulary.

### 4.2 Track manifests (`scripts/issue-workflow/v2/tracks/*.md`)

One file per track declaring: phases to run, agents per phase, parallelism budget,
required artifacts, gates. S = brief→implement→PR (CI is the only review gate).
M = full pipeline. L = M + spike + plan-critic + stacked-PR option. The conductor
reads the manifest to know what to dispatch; adding a step = editing a manifest.

### 4.3 Sandbox templates (`scripts/issue-workflow/v2/templates/`)

- `base.Dockerfile`: `node:24-bookworm-slim` + pi (`npm i -g
  @earendil-works/pi-coding-agent`) + git + ripgrep + jq. No credentials baked in.
- One thin layer per role adding only that role's `.pi/prompts` and `.pi/skills`
  (e.g. reviewers get the `golang-*` skills, mirroring CI's clone of
  `samber/cc-skills-golang`; researchers get none).
- Role → sandbox spec table (mount, network allow-list) lives in
  `scripts/issue-workflow/v2/README.md` and is enforced by the dispatch script, not
  by convention.

### 4.4 Dispatch primitive

`scripts/issue-workflow/v2/dispatch.sh <issue> <role> <brief-path>`:

1. Reads the role spec (mounts, network, image).
2. Creates the named sandbox `issue-<issue>-<role>` if absent (`sbx create …`),
   applying the role's network policy.
3. Runs `sbx exec <name> pi -p @<brief> "<role prompt>" --mode json`, streaming the
   event log to `docs/issue-workflows/<N>/agents/<role>.jsonl`.
4. On exit: updates `workflow.json` (state + telemetry), prints a 5-line summary and
   the next command.

## 5. Naming convention

Agreed 2026-08-13. One system covers commands, roles, states, files, and sandboxes.

**Rules:**

1. **Human commands are `<domain>-<verb>`** (kubectl-style: the noun groups, the
   verb acts). Full set: `/issue-start`, `/issue-research`, `/issue-plan`,
   `/issue-implement`, `/issue-review`, `/issue-open-pr`, `/issue-archive`,
   `/issue-next`.
2. **Namespaces are reserved by pattern.** `issue-*` = human lifecycle commands.
   Role families: `*-researcher` (research), `plan-*` (planning), `task-*`
   (implementation), `reviewer-*` (final-review panel).
3. **Roles are files, not commands.** `.pi/prompts/` holds human commands only;
   role contracts live at `scripts/issue-workflow/v2/roles/<role>.md` and are
   injected by `dispatch.sh`.
4. **Singular = system, plural = instances.** `scripts/issue-workflow/`,
   `docs/agents/issue-workflow.md` = the machinery; `docs/issue-workflows/<N>/` =
   runs.
5. **Casing per layer:** kebab-case for commands, roles, docs; `snake_case` for
   shell scripts and JSON keys.

**States — one vocabulary per level, no cross-level homonyms:**

- Board (GitHub-imposed, unchanged): `backlog → ready → in_progress → in_review →
  done`
- Agents (`workflow.json`): `queued → running → reported → done`; exceptional
  `blocked`, `failed`
- Phases: `pending → running → gated → done` (`gated` = awaiting human approval;
  `reported` = agent output awaiting acceptance)

**v1 → v2 mapping:**

| v1 | v2 |
|---|---|
| `/start-issue` | `/issue-start` |
| `/gather-context` | `/issue-research` |
| `/plan-issue` | `/issue-plan` |
| `/implement-task` | `/issue-implement` (drives `task-implementer`) |
| `/review-task` | absorbed into `/issue-implement` (`task-reviewer` role) |
| `/final-review` | `/issue-review` |
| `/open-pr` | `/issue-open-pr` |
| `/archive-issue` | `/issue-archive` |
| `/review-correctness` and siblings | `roles/reviewer-correctness.md` etc. (files, not commands) |
| `scout` | `repo-researcher` |
| `librarian` | `kb-researcher` |
| `implementer` | `task-implementer` |
| tmux "orchestrators" ×2 | `conductor` |
| `query_ready.sh <N>` | `get_item.sh` (status-agnostic lookup) |
| `query_ready.sh` (no args) | `pick_ready.sh` |
| `move_status.sh` | `set_status.sh` |
| agent state `working` | `running` |
| agent state `review` | `reported` |

**Paths and names:**

- Sandboxes: `issue-<N>-<role>` (e.g. `issue-46-repo-researcher`) — full form,
  self-documenting in `sbx ls`.
- Worktrees: `.worktrees/issue-<N>` (git-ignored).
- Research dirs keep topic slugs with a mandatory ordering prefix:
  `research/<NN>-<slug>/` (e.g. `research/01-map-ledger-seams/`); one role may own
  several topics.
- The `workflow.json` agents map is keyed by topic/task id, with the role as a
  field.

**Glossary** (goes into the rewritten `docs/agents/issue-workflow.md`, Task 5.1):

| Term | Meaning |
|---|---|
| workflow | the system described here |
| run | one issue's passage through the workflow |
| phase | one stage of a run (research, plan, implement, review, pr) |
| role | a specialized subagent contract (a file) |
| dispatch | one headless execution of a role inside a sandbox |
| track | S/M/L sizing of a run |
| gate | a human approval point (backlog, plan, PR) |

## 6. Phases and tasks

### Phase 0 — Hardening + spikes (foundation, no behavior change to the workflow)

**Task 0.1 — Script fixes.** Split `query_ready.sh` into a status-agnostic lookup
(prints number/title/item_id/status) plus a separate unnumbered Ready pick; make
the start command assert `status == Ready` for a supplied issue; make `open_pr.sh`
refuse a branch not matching `feat/<issue>-*`; add `/docs/issue-workflows/` to
`.gitignore`; kill tmux sessions in the open-pr and archive flows; fix the stale
`/.agents` gitignore comment; remove or wire the dead `labels` block in
`config.json`. (Names here are v1 names; Task 0.5 renames per §5.)
*Acceptance:* each fix has a demonstrated before/after; `shellcheck` clean; existing
prompts updated to any changed script interfaces.

**Task 0.2 — Machine-checkable review gate.** `reviews/summary.md` gains frontmatter
(`status: green|red`, `blocking_unresolved: <int>`, `reviewed_head: <sha>`); add
`check_review_gate.sh <issue>` (exit 0/1); wire it into `/open-pr` step 1.
*Acceptance:* `/open-pr` on a red summary stops without LLM judgement involved.

**Task 0.3 — Spike: pi in sbx.** Build `base.Dockerfile`; create a sandbox against
this repo read-only; run `pi -p` headless inside via `sbx exec`; capture JSON event
log on the host; confirm model auth flows through the sbx credential proxy (no key
material inside the sandbox image or filesystem).
*Acceptance:* a one-page spike report (`docs/issue-workflows/spike-sbx.md` — delete
after Phase 1) answering: template build time, sandbox create/exec latency, `pi -p`
exit behavior, log streaming, credential proxy mechanics. Any answer that breaks a
§4 assumption → stop and report.

**Task 0.4 — Spike: vault + context7 from sandboxes.** Mount the league-tokens vault
`:ro` and read a note from inside; run a context7 query from inside a sandbox with a
network allow-list limited to the context7 endpoint.
*Acceptance:* both demonstrated; the exact `sbx policy allow network` arguments are
recorded for the dispatch script.

**Task 0.5 — Naming migration (atomic).** Apply §5 in one sweep so the repo never
has broken cross-references: rename the prompt templates per the mapping table
(`/start-issue` → `/issue-start`, etc.); move the five `/review-*` role prompts to
`scripts/issue-workflow/v2/roles/` as plain contract files; rename scripts
(`query_ready.sh` → `get_item.sh` + `pick_ready.sh`, `move_status.sh` →
`set_status.sh`); update every caller (prompt bodies, scripts, README,
docs/agents/*); add the §5 glossary to `docs/agents/issue-workflow.md`.
*Acceptance:* the pi slash menu shows only `/issue-*` workflow commands; a grep for
the v1 names across `.pi/`, `scripts/`, `docs/` returns only historical references;
`shellcheck` clean; the v1 workflow still runs end-to-end under the new names.

### Phase 1 — Research phase in sbx (first user-visible win)

**Task 1.1 — Role contracts.** Four role files under
`scripts/issue-workflow/v2/roles/` (`repo-researcher`, `docs-researcher`,
`web-researcher`, `kb-researcher`) with a shared report contract: question, sources
consulted, findings, contradictions-with-other-sources, open questions, plus the
"TL;DR for humans" header. `web-researcher`'s contract must label all output
non-authoritative inspiration.
*Acceptance:* each role file fits on one screen; each names its report path
`research/<NN>-<slug>/report.md`.

**Task 1.2 — Research dispatch.** `dispatch.sh` (§4.4) + role specs + a conductor
command `/issue-research <N>` that: creates `workflow.json` if absent, dispatches
the approved research backlog in parallel (≤4), collects reports, updates state and
telemetry.
*Acceptance:* on a test issue, four sandboxes run concurrently; reports and
`workflow.json` land correctly; `sbx ls` shows the four named sandboxes.

**Task 1.3 — Migrate `/gather-context`.** The existing context orchestrator keeps
its Phase 1 (propose backlog, human approval) but dispatches via Task 1.2 instead of
tmux workers; `context-synthesizer` writes `context.md` per the existing
ORCHESTRATOR.md Phase 3 contract (now including a mandatory *Contradictions* and
*TL;DR for humans* section).
*Acceptance:* end-to-end on a real Ready issue: backlog gate → parallel research →
`context.md` approved; zero tmux windows created.

### Phase 2 — Conductor, state machine, tracks

**Task 2.1 — Conductor prompt + `/issue-next`.** One interactive prompt encoding:
the state machine over `workflow.json`, the track manifests, gate presentation
(summary + exact next command), and amend-brief/re-dispatch failure handling.
`/issue-next <N>` reads state and runs the next phase; explicit phase commands
(`/issue-start`, `/issue-research`, `/issue-plan`, `/issue-implement`,
`/issue-review`, `/issue-open-pr`, `/issue-archive`) remain.
*Acceptance:* from any state, `/issue-next` does the right thing or says precisely
what blocks it.

**Task 2.2 — Tracks.** Write the three manifests; conductor proposes a track at
intake from signals (size label, AC count, contexts touched, ambiguity) and records
human confirmation + any mid-flight changes in `track_history`.
*Acceptance:* a Track S issue runs brief→implement→PR with no local review phase; a
Track L issue includes the plan-critic pass.

**Task 2.3 — `plan-critic` role.** Fresh-eyes adversarial review of `plan.md` +
briefs: missing edge cases, untestable acceptance criteria, tasks exceeding the LOC
budget, unexamined alternatives. Writes `plan-critic.md`; the planner (or human)
must disposition every finding (accept/revise/reject-with-reason) in the plan.
*Acceptance:* on a Track L issue, the critic report exists and every finding has a
recorded disposition.

**Task 2.4 — Planner budgets.** `/issue-plan` enforces reviewability budgets (task ≈
one commit ≲ 300 LOC; PR ≲ 800 LOC) and required brief sections, adding the TL;DR
header to briefs.
*Acceptance:* planner output violating budgets is self-flagged with a split
proposal instead of silently oversized.

### Phase 3 — Implementation in a worktree sandbox

**Task 3.1 — Worktree plumbing.** Conductor creates `git worktree add
.worktrees/issue-<N> feat/<N>-…` (git-ignored), mounts it rw into the
task-implementer sandbox; the main checkout is never touched by the
task-implementer.
*Acceptance:* a commit made inside the sandbox appears in the host worktree; the
main checkout is untouched; no GitHub credentials exist inside the sandbox
(verify with `env` + a deliberately failing `git push` inside).

**Task 3.2 — Headless task-implementer + task-reviewer.** Migrate `/implement-task`
and `/review-task` semantics into role files (`roles/task-implementer.md`,
`roles/task-reviewer.md`): implement exactly the brief; stage only intended
changes; the reviewer commits on green using conventional commits referencing
issue + task, e.g. `feat: add session validation (#46, task 01)`; task state
tracked in `workflow.json`.
*Acceptance:* a two-task plan executes fully headless; per-task commits are green on
typecheck + focused tests + full suite; failed review → fix loop works via
amend-brief/re-dispatch.

### Phase 4 — Final review in sbx + incremental re-review

**Task 4.1 — Five reviewers as role files.** Port the existing `/review-*` rubrics
into `roles/reviewer-*.md` files whose images include the matching `golang-*`
skills (parity with CI). Parallel dispatch (≤5), reports to `reviews/<focus>.md`
as today.
*Acceptance:* findings quality on a known-buggy test diff is at least parity with
the tmux version; skills are actually loaded inside the sandbox.

**Task 4.2 — Incremental re-review.** Each report records `reviewed_head`; a
re-review dispatch diffs `reviewed_head..HEAD` for fix verification while keeping
whole-diff context available; `summary.md` carries the Task 0.2 frontmatter.
*Acceptance:* second review round consumes measurably fewer tokens (telemetry shows
it) and still catches a planted regression.

### Phase 5 — Retire tmux, finish docs, close the loop

**Task 5.1 — Deletion and docs.** Remove `context/`, `final-review/` tmux machinery
and retired scripts; rewrite `docs/agents/issue-workflow.md` for v2 (including
`/issue-archive` in the lifecycle — it is undocumented there today — and the §5
glossary); update `scripts/issue-workflow/README.md`, and AGENTS.md if needed.
*Acceptance:* `grep -rn tmux docs/ scripts/ .pi/` shows only historical references;
a newcomer can run the v2 workflow from the docs alone.

**Task 5.2 — Archive + feedback loop.** `/issue-archive` removes the issue's
sandboxes (`sbx rm issue-<N>-*`), appends telemetry totals to the landing note, and
its lesson-mining step explicitly checks recurring review findings for
prompt/skill updates.
*Acceptance:* after archiving a finished issue: zero sandboxes remain (`sbx ls`),
the landing note carries the telemetry block, and any recurring finding has a lesson
candidate drafted.

**Task 5.3 — Dogfood.** Run one real Ready issue per track through v2 (suggested: a
chore for S, e.g. #41 `slog structured logging` for M, and an L candidate when one
appears). File follow-up issues for every friction point found.
*Acceptance:* three PRs merged via v2; telemetry reviewed; at least one tuning
adjustment shipped from the data.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| pi is not a first-class sbx agent; template/exec behavior unknown | Phase 0 spikes gate everything; stop-and-report on contradiction |
| microVM startup makes dispatch feel slow | Long-lived named sandboxes per issue; measure in telemetry |
| Headless agents fail silently | JSON event log per dispatch + `failed` state + amend-brief/re-dispatch; `sbx exec -it` escape hatch |
| Web-researcher pollutes context with low-quality inspiration | Non-authoritative label in its contract; synthesizer must attribute sources; human gate on backlog |
| Track S erodes review culture | CI gate must stay healthy; revisit if Track S PRs bounce in CI |
| Sandbox drift (stale images, leftover sandboxes) | `sbx rm issue-<N>-*` at archive; images rebuilt when pi/skills change |

## 8. Open questions the spikes must answer

1. Exact `sbx create`/`sbx exec` invocation for headless pi (flags, TTY needs, exit
   codes, log streaming).
2. Credential proxy mechanics for pi's model provider env vars (which vars the proxy
   injects; what placeholder values the template needs).
3. Worktree + `:ro` mount behavior for the main checkout alongside an rw worktree
   mount (any path-collision quirks).
4. context7 endpoint allow-list shape for `sbx policy allow network`.
5. Whether `sbx exec` output streaming is sufficient for progress display, or the
   conductor should poll the status files instead.
