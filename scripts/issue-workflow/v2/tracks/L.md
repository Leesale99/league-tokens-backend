track: L
phases: research,plan,implement,review,pr
parallelism.research: 4
parallelism.review: 5
agents.research: repo-researcher,docs-researcher,web-researcher,kb-researcher
agents.plan: context-synthesizer,planner,plan-critic
agents.implement: task-implementer,task-reviewer
agents.review: reviewer-correctness,reviewer-quality,reviewer-quality-depth,reviewer-security,reviewer-requirements
artifacts: research/*/report.md,context.md,plan.md,plan-critic.md,tasks/*.md,reviews/summary.md
gates: backlog,plan,pr
spike: true
plan_critic: true

# Track L — large/uncertain

M plus three options:

- **Spike step** — a throwaway prototype in a scratch sandbox before
  planning, to retire the largest uncertainty (Task 2.2 declares it; the
  execution machinery lands with the conductor's spike support).
- **plan-critic pass** — a fresh-eyes adversarial review of `plan.md` and
  the task briefs after planning; every finding is dispositioned
  (accept/revise/reject-with-reason) in the plan (Task 2.3).
- **Stacked PRs** — the stacked-PR option when the issue exceeds the PR
  reviewability budget (~800 LOC).
