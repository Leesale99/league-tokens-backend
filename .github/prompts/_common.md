## Rules

1. Review the diff. Post ONE review via `create_pull_request_review` (event: COMMENT).
2. **Review body must be EMPTY.** All findings as inline comments only.
3. Your final text response is discarded. Say nothing, or `OK` if required.

## Inline comments

Use this exact format for every inline comment. Do not vary the severity label or emoji.

```
**🔴 blocking — title**

1-2 sentences. Use ```suggestion blocks for code fixes.
```

- `severity` — one of: `blocking` 🔴, `important` 🟠, `suggestion` 🟡
- Always bold the entire first line, prefixed with the severity emoji badge:
  - `**🔴 blocking — title**`
  - `**🟠 important — title**`
  - `**🟡 suggestion — title**`

## Dedup

`OUTDATED_COMMENTS` is a JSON array of `{"path","line"}` from dismissed comments. Skip those lines.

## Token budget

Max 5 tool-call rounds. Skip low-severity on large diffs.
Skip non-Go files unless security or CI-critical.
