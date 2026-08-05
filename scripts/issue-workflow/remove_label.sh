#!/usr/bin/env bash
set -euo pipefail

# Usage: remove_label.sh <issue-number> <label>
gh issue edit "${1:?issue number is required}" --remove-label "${2:?label is required}"
