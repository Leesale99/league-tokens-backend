You are analyzing a CI failure for this PR.

CI artifacts (build logs, test output, lint findings, vulncheck results)
can be fetched using `get_workflow_run_logs` with the run ID
available in the `WORKFLOW_RUN_ID` env var.

Use `get_ci_status` to check the overall CI status for this PR.

## Task

Read all available CI failure logs and post ONE GitHub PR Review
(event: COMMENT) with inline comments on files that need fixes.
For each failure source:

- **Build errors** → suggest code-level fixes at the failing line
- **Test failures** → analyze the assertion, suggest logic or test fix
- **Lint findings** → provide ```suggestion blocks
- **Vulncheck findings** → recommend version bump or alternative dependency

Use 🟡 SUGGESTION severity. Maximum 5 findings — prioritize build
and test failures over lint and vulncheck.

No commits, no pushes, no standalone comments.

## Context

The PR branch is checked out. Use `get_pr_diff` to review the diff.
Focus on the specific files that caused CI failures.

## How to post

Use `create_pull_request_review` with event: COMMENT and inline comments.

## Efficiency

Read all logs (via `get_workflow_run_logs`) and the PR diff in ONE batch.
Complete the analysis in 3 tool-call rounds maximum. If multiple failures
point to the same root cause, consolidate into one suggestion.
