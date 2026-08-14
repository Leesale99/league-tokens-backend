track: M
phases: research,plan,implement,review,pr
parallelism.research: 4
parallelism.review: 5
agents.research: repo-researcher,docs-researcher,web-researcher,kb-researcher
agents.plan: context-synthesizer,planner
agents.implement: task-implementer,task-reviewer
agents.review: reviewer-correctness,reviewer-quality,reviewer-quality-depth,reviewer-security,reviewer-requirements
artifacts: research/*/report.md,context.md,plan.md,tasks/*.md,reviews/summary.md
gates: backlog,plan,pr
spike: false
plan_critic: false

# Track M — standard

Full pipeline: research (≤4 parallel) → plan → implement (sequential) →
final review (≤5 parallel) → PR. Three human gates: research backlog,
plan, PR.
