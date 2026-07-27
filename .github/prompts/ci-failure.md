REPO: $REPO
PR NUMBER: $PR_NUMBER

You are analyzing a CI failure for this PR. CI artifacts
(build logs, test output, lint findings, vulncheck results)
are available in the runner workspace under /tmp/ci-artifacts/.

## Task

Read all available CI failure artifacts and post ONE GitHub PR
Review (event: COMMENT) with inline comments on files that need
fixes. For each failure source:

- **Build errors** → suggest code-level fixes at the failing line
- **Test failures** → analyze the assertion, suggest logic or test fix
- **Lint findings** → provide ```suggestion blocks
- **Vulncheck findings** → recommend version bump or alternative dependency

Use 🟡 SUGGESTION severity. Maximum 5 findings — prioritize build
and test failures over lint and vulncheck.

No commits, no pushes, no standalone comments.

## Context

The PR branch is checked out. Use `gh pr diff $PR_NUMBER` to review
the diff. Focus on the specific files that caused CI failures.

## How to post

Use this exact command — do NOT use `gh pr comment`:

```bash
gh api repos/$REPO/pulls/$PR_NUMBER/reviews \
  --input - << 'JSONEOF'
{
  "event": "COMMENT",
  "body": "CI failure analysis — see inline comments for remediation.",
  "comments": [
    {
      "path": "path/to/file.go",
      "line": 42,
      "side": "RIGHT",
      "body": "CI failing here: <reason>\n\n```suggestion\n<fix>\n```"
    }
  ]
}
JSONEOF
```

## Efficiency

Read all artifact files and the PR diff in ONE batch. Complete
the analysis in 3 tool-call rounds maximum. If multiple failures
point to the same root cause, consolidate into one suggestion.
