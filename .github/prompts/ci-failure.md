You are analyzing a CI failure for this PR.

CI artifacts (build logs, test output, lint findings, vulncheck results)
can be fetched using `get_workflow_run_logs` with the run ID
available in the `WORKFLOW_RUN_ID` env var.

Use `get_ci_status` to check CI status for this PR.

## Task

1. Read all available CI failure logs using `get_workflow_run_logs`.
2. Review the PR diff below.
3. Post ONE review using `create_pull_request_review` (event: COMMENT).
   Body: `## CI Failure Analysis` — nothing more.
   All findings go as inline comments.

No commits, no pushes, no standalone issue comments.

## Output discipline (CRITICAL)

- No preambles, no meta-commentary, no self-narration.
- Output only the analysis after inline comments.
- 3-5 sentences max.

## Analysis

For each failure source:

- **Build errors** → suggest code-level fixes at the failing line
- **Test failures** → analyze the assertion, suggest logic or test fix
- **Lint findings** → provide ```suggestion blocks
- **Vulncheck findings** → recommend version bump or alternative dependency

Use 🟡 SUGGESTION severity. Max 5 findings. Prioritize build and test
over lint and vulncheck.

## Context

The PR branch is checked out. Focus on the files that caused CI failures.

## Efficiency

- Read all logs and diff in ONE batch.
- Max 3 tool-call rounds. Consolidate failures with the same root cause
  into one suggestion.
