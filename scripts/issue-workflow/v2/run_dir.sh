#!/usr/bin/env bash
# Usage: run_dir.sh <issue> — prints the issue's run directory (host path).
#
# The run dir lives OUTSIDE the repo (<repo>/../issue-workflows/<N>) so a
# role sandbox can mount the repo root :ro while its rw primary lives
# elsewhere — sbx/virtiofs gives EROFS on a rw workspace nested inside a
# :ro mount (host acceptance, Phase 1). The conductor's sandbox mounts
# this location rw alongside the repo, so the conductor reads and writes
# run dirs at the same absolute host paths. v1 scripts keep
# docs/issue-workflows/ until Phase 5 retires them.
set -euo pipefail

issue="${1:?issue number is required}"
repo_root="$(git rev-parse --show-toplevel)"
work_root="$(cd "$(dirname "$repo_root")" && pwd)/issue-workflows"
printf '%s/%s\n' "$work_root" "$issue"
