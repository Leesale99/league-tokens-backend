# Issue Workflow v2 — Design: Sandboxed Subagents and Sized Tracks

Status: Accepted
Date: 2026-08-13
Deciders: backend architect, product owner

> Process-infrastructure design, not product architecture — deliberately kept out of
> the `docs/adr/` series, which is reserved for the Go backend system. Companion
> implementation plan: `docs/agents/issue-workflow-v2-plan.md`. Once v2 ships, the
> distilled decision and lessons flow into the vault decision log as history.

## Context

The issue workflow (`docs/agents/issue-workflow.md`) exists to solve four recurring
problems with agent-driven development:

1. **Agents write huge PRs** that humans cannot understand or review.
2. **Agents answer from stale pre-trained knowledge.** We want decisions grounded in
   fresh, multi-source research: local repo, external documentation (context7), web
   research for inspiration and alternate angles, and the knowledge base for history.
3. **Agents work autonomously without an approved plan.** The workflow must be
   teamwork: invest effort upfront in context gathering and planning ("pay at the
   beginning") instead of generating code fast and repairing it in review
   ("pay at the end", which produces fix-forward slop out of sync with the whole).
4. **The project is educational** for humans and agents: share and evaluate different
   approaches, hunt edge cases, brainstorm, and record agreed best practices.

The current workflow already has the right skeleton — an artifact chain
(`issue.md → research/ → context.md → plan.md → tasks/ → reviews/`) with human
approval gates — but its plumbing is under strain:

- tmux-orchestrated interactive workers leak state and sessions (dead workers hold
  `working` slots forever; sessions are never cleaned up; duplicate dispatch races on
  report files).
- Web research does not exist at all; context7 is not wired to any researcher;
  knowledge-base lookup is a bullet point, not a first-class role.
- Every issue runs the full ceremony regardless of size.
- The final-review gate is prose-judged by an LLM, re-review re-reads the whole diff,
  and there is no telemetry to tune the process with.

## Decision

### Artifact-centric lifecycle, few meaningful gates

- Keep the artifact chain unchanged: `issue.md → research/ → context.md → plan.md →
  tasks/ → reviews/` → PR → vault archive on close.
- **Artifacts are the interface between phases.** An agent reads the self-contained
  document of its phase, never the transcript of a previous phase.
- Every artifact opens with a **"TL;DR for humans"** section (what was decided, why,
  which alternatives were rejected) so the workflow stays educational and reviewable.
- Exactly **three human gates**: research-backlog approval, plan approval, PR
  approval. Everything between gates runs unattended — more gates would train
  rubber-stamping.

### One interactive conductor; headless sandboxed subagents

- A single interactive **conductor** runs on the host and is the only agent the human
  talks to. It owns the workflow state machine, dispatches subagents, collects
  artifacts, and presents gate summaries. It does no research or implementation
  itself. Only the conductor session may be interactive (optionally in tmux).
- All work agents run **headless inside Docker Sandboxes (sbx)** microVMs:
  `sbx create` once per role per issue, `sbx exec <name> pi -p …` per dispatch.
  Mid-flight steering of headless agents is an anti-pattern: amend the brief and
  re-dispatch. Manual escape hatch is always available via `sbx exec -it <name> bash`.
- tmux is retired as the orchestration mechanism once migration completes.

### Subagent roster — specialization along capability boundaries

Research (parallel, read-only mounts):

| Role | Job | Mounts | Network |
|---|---|---|---|
| `repo-researcher` | repo cartography: code paths, tests, seams, terminology | repo `:ro` | none |
| `docs-researcher` | dependency/API facts via context7; installed vs. current docs | repo `:ro` | context7 only |
| `web-researcher` | approaches, prior art, edge cases; output labeled **non-authoritative** | repo `:ro` | search providers only |
| `kb-researcher` | vault history: decisions, lessons, archived issues | vault `:ro` | none |

Planning (sequential): `context-synthesizer` (merge reports; surface contradictions
and open questions, never paper over them), `planner` (plan + self-contained task
briefs, iterating with the human), **`plan-critic`** (a real separate role:
fresh-eyes adversarial pass for missing edge cases, untestable criteria, oversized
tasks).

Implementation (sequential): `task-implementer` (one task brief → one commit, tests
run inside the sandbox) and `task-reviewer` (staged diff vs. acceptance criteria).

Final review (parallel, read-only): `reviewer-correctness`, `reviewer-quality`,
`reviewer-quality-depth`, `reviewer-security`, `reviewer-requirements` — kept in
parity with the CI review pipeline so local and CI findings stay comparable.

### Sandbox patterns

- **Custom sbx template images**: a common base (Node 24 + pi + git + ripgrep + jq)
  with a thin layer per role adding only that role's skills and prompt. sbx scopes
  filesystem/network/credentials; the **image scopes the agent's toolbox**.
- Per-sandbox network allow-lists via `sbx policy allow network` (see roster table).
- **No sandbox holds GitHub write credentials.** The conductor snapshots issues and
  opens PRs from the host; the task-implementer commits into a mounted **git
  worktree** of the feature branch and never pushes. Model API keys enter sandboxes
  only through the sbx credential proxy.
- Sandboxes are named and long-lived within an issue (create at phase start, exec
  many times, remove at archive) to amortize microVM startup.

### Sized tracks

- **Track S (trivial)**: brief → implement → PR. No local final review; the **CI
  pipeline is the only review gate**.
- **Track M (standard)**: full pipeline.
- **Track L (large/uncertain)**: M plus spike/prototype step, `plan-critic` pass, and
  optionally stacked PRs.
- The conductor **proposes** a track from signals (size label, acceptance-criteria
  count, bounded contexts touched, ambiguity); the human **confirms** at the first
  gate — the sizing discussion is itself a teaching moment. Tracks may be
  escalated/de-escalated mid-flight; the change and its reason are recorded.
- **Reviewability budgets** enforced by the planner: task ≈ one commit ≲ 300 LOC
  diff; issue ≈ one PR ≲ 800 LOC; overflow → split the issue or design stacked PRs.
- Each track is defined by a small manifest (phases, agents, parallelism budget,
  required artifacts). Manifests are the extension mechanism for new steps/roles.

### State, triggers, telemetry

- `workflow.json` per issue: track, current phase, per-agent state, reviewed-HEAD per
  reviewer (enables **incremental re-review** instead of whole-diff re-reads), and
  **per-phase token/time telemetry** from day one.
- Explicit phase commands plus `/issue-next <N>`, which reads state and runs the
  next phase. Each phase ends by printing a human summary and the exact next command.

### Naming

One convention covers commands, roles, states, and paths (full rules and the
v1→v2 mapping live in the plan, §5):

- Human commands are `<domain>-<verb>`: `/issue-start`, `/issue-research`,
  `/issue-plan`, `/issue-implement`, `/issue-review`, `/issue-open-pr`,
  `/issue-archive`, `/issue-next`.
- Role names are functional and grouped in families (`*-researcher`, `plan-*`,
  `task-*`, `reviewer-*`). Roles are contract files, not slash commands;
  `.pi/prompts/` holds human commands only.
- States use one vocabulary per level: agents `queued → running → reported → done`
  (exceptional `blocked`, `failed`); phases `pending → running → gated → done`.
- Sandboxes are named `issue-<N>-<role>`. Singular paths name the system
  (`scripts/issue-workflow/`), plural paths name its instances
  (`docs/issue-workflows/<N>/`).

### Source authority hierarchy

repo + ADRs (constraints, authoritative) → context7 (dependency facts) → vault
(history) → web (inspiration, non-authoritative). Contradictions between sources are
surfaced in `context.md` for the human; agents never silently resolve them.

### Feedback loop

Recurring review findings flow back into vault lessons and from there into
prompt/skill updates. This is an explicit, mandatory step of issue archival, not an
afterthought.

## Consequences

- Positive: bounded blast radius per agent (fs/network/credential scoping); decisions
  grounded in fresh multi-source research; small reviewable PRs by construction;
  human attention concentrated at three gates and one conductor; telemetry enables
  evidence-based tuning; no GitHub credentials ever leave the host.
- Negative: microVM startup latency per dispatch (mitigated by long-lived named
  sandboxes); more moving parts to operate (templates, network policies); pi is not a
  first-class sbx agent, so a custom template is required; headless subagents give up
  mid-flight steering (mitigated by amend-brief/re-dispatch and the `sbx exec`
  escape hatch); Track S relies on CI review quality, which must be kept healthy.

## Alternatives considered

- **Keep tmux interactive workers.** Rejected: state/session leaks, weak isolation,
  and it cannot cleanly host parallel research with per-role network policies.
- **Ground-up rewrite around an external orchestrator service.** Rejected: the
  artifact chain and gates already embody the target philosophy; only the plumbing
  needed replacing.
- **One subagent per micro-job.** Rejected: cold-start cost and handoff context loss;
  specialization follows capability boundaries instead.
- **Fully automatic track sizing.** Rejected: track confirmation is a human gate and
  an educational moment.
- **Read-write repo mounts for every agent.** Rejected: research and review agents
  get read-only mounts; only the implementer gets a worktree, read-write.
