#!/usr/bin/env bash
# Pure aggregation: merges per-focus review-findings artifacts into a single
# deduplicated, severity-ranked JSON array on stdout. No GitHub writes — kept
# separate from report-and-gate.sh so the merge logic is unit-testable.
#
# Usage: FINDINGS_DIR=/path/to/artifacts .github/scripts/aggregate-findings.sh
# Output: JSON array of {severity, path, line, title, body}
set -euo pipefail

FINDINGS_DIR="${FINDINGS_DIR:-}"
all_findings='[]'

if [ -z "$FINDINGS_DIR" ] || [ ! -d "$FINDINGS_DIR" ]; then
  echo '[]'
  exit 0
fi

shopt -s nullglob
for f in "$FINDINGS_DIR"/*/review-findings.json; do
  [ -f "$f" ] || continue
  n=$(jq 'length' "$f" 2>/dev/null || echo 0)
  echo "  $(basename "$(dirname "$f")"): $n finding(s)" >&2
  all_findings=$(jq -cs 'add' <(printf '%s' "$all_findings") <(cat "$f") 2>/dev/null || echo "$all_findings")
done
shopt -u nullglob

# Dedup by (path, line): cross-job findings on the same line are almost
# always the same finding (PR #83: 4 differently-worded phrasings of one
# compile error on line 39), so a title-based key would keep all of them.
# Highest severity wins (blocking > important > suggestion); ties keep the
# most detailed body. Output is ranked by severity, then path, then line.
#
# Note: severity is precomputed into a numeric `_sev` field rather than
# referenced through a def inside the final sort_by — jq 1.7 breaks on a
# user-defined filter as the first key of a multi-key sort_by.
echo "$all_findings" | jq -c '
  def sev: if . == "blocking" then 0 elif . == "important" then 1 else 2 end;
  map(. + {_sev: (.severity | sev), _len: ((.body // "") | length)}) |
  group_by(.path, .line) |
  map(sort_by(._sev, -._len) | .[0] | del(._sev, ._len)) |
  sort_by(.severity, (.path // ""), (.line // 0))
'
