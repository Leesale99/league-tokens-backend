#!/usr/bin/env bash
set -euo pipefail

# Usage: add_label.sh <issue-number> <label>
gh issue edit "${1:?issue number is required}" --add-label "${2:?label is required}"
