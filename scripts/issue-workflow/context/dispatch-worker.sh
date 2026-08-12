#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   dispatch-worker.sh <issue-number> <todo-id> <scout|architect|docs-auditor>
#
# Worker context is deliberately split into three layers:
#   1. role skill       -> how this role investigates
#   2. brief.md         -> what this specific todo investigates
#   3. runtime prompt   -> operational constraints and completion protocol

issue_number="${1:?issue number is required}"
todo_id="${2:?todo id is required}"
role="${3:?role is required}"

repo_root="$(git rev-parse --show-toplevel)"
session="issue-$issue_number-context"
todo_dir="$repo_root/docs/issue-workflows/$issue_number/research/$todo_id"
brief="$todo_dir/brief.md"
status="$todo_dir/status.json"
skill="$repo_root/scripts/issue-workflow/skills/$role/SKILL.md"

case "$role" in
scout | architect | docs-auditor) ;;
*)
  echo 'Role must be scout, architect, or docs-auditor.' >&2
  exit 1
  ;;
esac

if ! tmux has-session -t "$session" 2>/dev/null; then
  printf 'Context tmux session does not exist: %s\n' "$session" >&2
  exit 1
fi

if [[ ! -f "$brief" ]]; then
  printf 'Missing worker brief: %s\n' "$brief" >&2
  exit 1
fi

if [[ ! -f "$skill" ]]; then
  printf 'Missing role skill: %s\n' "$skill" >&2
  exit 1
fi

if [[ -f "$status" ]]; then
  current_state="$(jq -r '.state // empty' "$status")"
  if [[ "$current_state" != "queued" ]]; then
    printf 'Todo %s is %s; only queued todos can be dispatched.\n' "$todo_id" "$current_state" >&2
    exit 1
  fi
fi

working_count=0
for existing_status in "$repo_root/docs/issue-workflows/$issue_number/research"/*/status.json; do
  [[ -f "$existing_status" ]] || continue

  if [[ "$(jq -r '.state // empty' "$existing_status")" == "working" ]]; then
    ((working_count += 1))
  fi
done

if ((working_count >= 3)); then
  echo 'Three research workers are already working; wait for a slot before dispatching another.' >&2
  exit 1
fi

mkdir -p "$todo_dir"
printf '{"state":"working"}\n' >"$status"

worker_prompt="You are the $role worker for issue #$issue_number.

Your role skill has been explicitly supplied with --skill. Follow it as the
role-level methodology.

Your supplied worker brief is the task-specific contract for this todo. Treat
it as authoritative for the question, scope, research mode, evidence
requirements, and deliverables.

Work interactively: the user may steer you in this window.

Operational constraints:
- You may inspect repository and external sources as permitted by the role
  skill and worker brief.
- Modify only your own report.md and status.json.
- Do not edit product code, queue.md, context.md, or another worker's files.
- Do not silently resolve blockers by guessing.

When the investigation is complete:
1. write the structured report to report.md;
2. set status.json to {\"state\":\"review\"};
3. state that the report is ready for review."

brief_ref="@$brief"

printf -v worker_command \
  'cd %q && exec pi --approve --skill %q --name %q %q %q' \
  "$repo_root" \
  "$skill" \
  "Issue #$issue_number $role $todo_id" \
  "$brief_ref" \
  "$worker_prompt"

tmux new-window -d -t "$session:" -n "$todo_id" "$worker_command"

printf 'Worker started. Open it with:\n\ntmux select-window -t %s:%s\n' "$session" "$todo_id"
