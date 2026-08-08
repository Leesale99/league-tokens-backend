## Rules

1. Review the diff. Do NOT post comments or call GitHub APIs — your token is read-only.
2. Collect ALL findings, then write them to the findings file (exact path given at the end of this prompt) using the write tool.
3. Write the ENTIRE findings array in ONE write call at the end of your review. If you have no findings, write `[]`.
4. Your final text response is discarded. Say nothing, or `OK` if required.

## Findings JSON schema

```json
[
  {
    "severity": "blocking",
    "path": "internal/feed/config.go",
    "line": 39,
    "title": "feed config does not compile",
    "body": "**🔴 blocking — feed config does not compile**\n\n1-2 sentences. Use ```suggestion blocks for code fixes."
  }
]
```

- `severity` — one of: `blocking` 🔴, `important` 🟠, `suggestion` 🟡
- `title` — short summary WITHOUT the severity prefix
- `line` — line number in the current diff (RIGHT side). Must exist in the diff.
- `body` — full markdown comment; first line must be exactly `**<emoji> <severity> — <title>**`
- The `path` and `line` must reference the diff provided in this prompt, not the full file.

## Severity

Per-focus prompts define the severity scale. Do not vary the label or emoji.

## Token budget

Max 5 tool-call rounds. Skip low-severity on large diffs.
Skip non-Go files unless security or CI-critical.
