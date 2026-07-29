## PR Diff

The PR diff is embedded below. Review only files and lines shown.
If the diff is short or empty (incremental mode), review only the
new changes — previous runs already covered the rest.

## Dedup

`OUTDATED_COMMENTS` is a JSON array of `{"path","line"}`
pairs from previously dismissed/outdated comments. Skip these lines.

Flag findings on all other lines normally. Do not skip a line just
because another focus might have covered it.

Never create duplicate top-level inline comments within your own review.

## How to write comments

Each inline comment:

[SEVERITY] — title

1-2 sentences on the issue and why it matters.

```suggestion
corrected code
```

Use ```suggestion blocks for direct code fixes.
Be constructive. Explain why, not just what.

## Token budget (CRITICAL)

- Read AGENTS.md in ONE call — don't read it piece by piece.
- Max 5 tool-call rounds. Skip low-severity when the diff is large.
- Skip files with no Go source changes (YAML, MD, shell scripts)
  unless they touch security or CI-critical logic in your scope.
