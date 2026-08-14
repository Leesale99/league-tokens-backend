# Issue workflow support

The v2 issue workflow (`docs/agents/issue-workflow.md`) is driven by the
`/issue-*` prompts in `.pi/prompts/` and the scripts here. Everything runs
headless — no tmux, no interactive worker sessions. Per-issue records live
OUTSIDE the repo at `~/Projects/league-tokens/issue-workflows/<N>`
(resolved by `v2/run_dir.sh <N>`), so `git status` stays clean.

## Scripts

- `get_item.sh`, `pick_ready.sh`, `set_status.sh`: GitHub Project board
  operations. `get_item.sh <N>` is a status-agnostic lookup (`--expect
  <status>` asserts it); `pick_ready.sh` picks the first Ready item.
- `add_label.sh`, `remove_label.sh`: issue-label operations
  (`ready-for-agent`, `ready-for-human`, …).
- `capture_issue.sh`: immutable issue snapshot into the run dir
  (`<run>/issue.md`).
- `open_pr.sh`: v2 — resolves the issue worktree
  (`.worktrees/issue-<N>`), verifies it is clean and on
  `feat/<N>-*`, pushes the branch, and opens the PR. Never touches the
  main checkout.
- `check_review_gate.sh`: mechanical final-review gate; exits 0 only when
  `<run>/reviews/summary.md` frontmatter is `status: green`,
  `blocking_unresolved: 0`, and `reviewed_head` matches the worktree HEAD.
- `archive_issue.sh`: copies `<run>/` into the league-tokens vault as the
  raw archive tree `archive/<NNNN>-<slug>/` (the `/issue-archive` prompt
  writes the landing note + decisions/lessons and commits the vault).
- `config.json`: shared settings (branch prefix, …).
- `v2/`: the workflow machinery — `dispatch.sh` (role sandbox primitive),
  `research.sh`, `review.sh` (final review + incremental re-review),
  `next.sh` (state machine), `mark.sh` (state transitions), `worktree.sh`
  (feature-branch worktree), `run_dir.sh` (run-dir resolver), `roles/`
  (role contracts incl. the five reviewers), `tracks/` (S/M/L manifests),
  `templates/base.Dockerfile` (sandbox image), `spike/` (acceptance
  runners). See `v2/README.md`.

## Sandbox model (short version)

Every role runs in a disposable sbx sandbox created from the baked image
(`templates/base.Dockerfile`: node + Go 1.26 + git identity + the golang-*
review skills at `/opt/cc-skills-golang`). Role mounts are enforced by
`dispatch.sh`, never by convention: the repo is `:ro` (or the worktree for
task roles), the run dir is the rw primary (or `:ro` for task roles),
`.git` rw for task roles, the vault `:ro` for kb-researcher. Network is an
allow-list per role. Reports are written to paths the dispatch message
names; every verdict is report-first, never model output.
