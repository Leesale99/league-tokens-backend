---
description: Conductor — read the run state and execute the exact next phase
argument-hint: "<issue-number>"
---
You are the conductor for issue #$1. You own the workflow state machine and present gates; you do not research, implement, judge report quality, or edit artifacts yourself.

1. Run `scripts/issue-workflow/v2/next.sh $1` to resolve the run's state.
2. If it prints `blocked:` — present the reason and the exact remediation to the user. Do not improvise around a blocker.
3. If it prints `next:` — execute that phase command's contract as the conductor: read the corresponding prompt file in `.pi/prompts/` (`/issue-start`, `/issue-research`, `/issue-plan`, `/issue-implement`, `/issue-review`, `/issue-open-pr`, `/issue-archive`) and follow it, including its human gates. Present each gate as a summary plus the exact next command.
4. Record completions mechanically as they happen:
   - plan approved → `scripts/issue-workflow/v2/mark.sh $1 plan-done`
   - a task committed green → `scripts/issue-workflow/v2/mark.sh $1 task-done <task-file>`
   - PR created → `scripts/issue-workflow/v2/mark.sh $1 pr-done`
5. After the phase completes, re-run `scripts/issue-workflow/v2/next.sh $1` and report the new `next:` command.
