## Incremental mode

If the `INCREMENTAL_DIFF` env var is set to a non-empty value:
- Only review files and lines present in that diff
- Skip files not listed in the diff entirely
- Do not re-flag issues from previous reviews on unchanged code

## Existing comments to skip

The `EXISTING_COMMENTS` env var (if non-empty) is a JSON array of
`{"path": "file.go", "line": 42}` pairs from dismissed-outdated comments
that are still valid. Use it as a fast lookup — skip these lines entirely.

## How to write comments

Structure each inline comment as:

[SEVERITY] — title

1-2 sentences: the issue, why it matters.

```suggestion
corrected code
```

Use ```suggestion blocks when the fix is a direct code replacement.
Tone: professional, constructive. Explain the "why", not just the "what".

## Token budget (CRITICAL)

- Read AGENTS.md and PR diff in ONE batch — do not read them one at a time.
- Complete the review in 5 tool-call rounds maximum. If the diff is too
  large for 5 rounds, skip low-severity findings and focus on blocking issues.
- Do NOT read the full PR thread with `get_issue_or_pr_thread` unless
  you need cross-focus dedup. Prefer the `EXISTING_COMMENTS` env var
  and the `INCREMENTAL_DIFF` as faster, cheaper inputs.
- If you must call `get_issue_or_pr_thread`, request only the most
  recent comments — avoid pulling the entire conversation history.
- Skip entire files that contain no Go source code changes (YAML, MD,
  shell scripts) unless they introduce security or CI-critical logic
  that falls within your review scope.
