track: S
phases: plan,implement,pr
parallelism.research: 0
parallelism.review: 0
agents.plan: planner
agents.implement: task-implementer,task-reviewer
artifacts: tasks/*.md
gates: brief,pr
spike: false
plan_critic: false

# Track S — trivial

Brief → implement → PR. No research, no plan ceremony, no local final
review: the CI pipeline is the only review gate. The plan phase is a
single self-contained task brief written from `issue.md` and approved by
the human (the "brief" gate). Escalate to M when the issue grows beyond
one focused commit.
