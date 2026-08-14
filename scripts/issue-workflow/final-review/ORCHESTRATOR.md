# Final-review orchestrator

You coordinate independent final reviews for one issue. You do not fix findings yourself.

1. Read every Markdown file under `issue-workflows/<issue>/` (the run dir; resolve with v2/run_dir.sh), including all task briefs and approved context/plan material.
2. Confirm the current branch and comparison base (`origin/main...HEAD`, unless the issue documents another approved base). Record the exact diff command in `issue-workflows/<issue>/reviews/summary.md`.
3. Dispatch these five reviewers in parallel:

```bash
scripts/issue-workflow/final-review/dispatch-reviewer.sh <issue> correctness
scripts/issue-workflow/final-review/dispatch-reviewer.sh <issue> quality-depth
scripts/issue-workflow/final-review/dispatch-reviewer.sh <issue> quality
scripts/issue-workflow/final-review/dispatch-reviewer.sh <issue> security
scripts/issue-workflow/final-review/dispatch-reviewer.sh <issue> requirements
```

4. Each reviewer writes its own report at `issue-workflows/<issue>/reviews/<name>.md`. Let the user inspect or steer each interactive worker directly.
5. When every report exists, collect their findings without silently dismissing or reranking them. Write `reviews/summary.md` with links to all five reports, a deduplicated actionable finding list, and the frontmatter contract below.
6. Do not declare final review green until the user accepts the reports and every blocking finding is fixed and re-reviewed. Whenever you update the summary's status or finding list, refresh the frontmatter too — `/issue-open-pr` runs `check_review_gate.sh <issue>` mechanically and refuses a red, stale, or malformed summary without any LLM judgement. The implementation agent picks up reports from this directory.

### summary.md frontmatter contract (machine-checked by check_review_gate.sh)

Every version of `reviews/summary.md` opens with:

```
---
status: green|red
blocking_unresolved: <int>
reviewed_head: <sha>
---
```

- `status` — `green` only when the user accepted the reports and every blocking finding is fixed and re-reviewed; `red` otherwise.
- `blocking_unresolved` — count of blocking findings not yet fixed and re-reviewed.
- `reviewed_head` — the HEAD commit the current status applies to; refresh it whenever you update the summary.

The five reviewer role contracts live at `scripts/issue-workflow/v2/roles/reviewer-<focus>.md`. Preserve the report paths and workflow even while their review rubrics are customized later.
