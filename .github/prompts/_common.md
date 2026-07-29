## Rules

1. Review the diff. Post ONE review via `create_pull_request_review` (event: COMMENT).
2. **Review body must be EMPTY.** All findings as inline comments only.
3. Output a fenced JSON array as your final response. No other text — no narration, no thinking, no headings.

## JSON format

```json
[
  {
    "severity": "blocking",
    "path": "pkg/foo.go",
    "line": 42,
    "description": "error not checked — could panic on nil"
  }
]
```

- `severity` — `"blocking"` | `"important"` | `"suggestion"`
- `path` — relative to repo root
- `line` — integer (right-side of diff)
- `description` — one-line description of the issue

No findings → `[]`

## Inline comments

```
[SEVERITY] — title

1-2 sentences. Use ```suggestion blocks for code fixes.
```

## Dedup

`OUTDATED_COMMENTS` is a JSON array of `{"path","line"}` from dismissed comments. Skip those lines.

## Token budget

Max 5 tool-call rounds. Skip low-severity on large diffs.
Skip non-Go files unless security or CI-critical.
