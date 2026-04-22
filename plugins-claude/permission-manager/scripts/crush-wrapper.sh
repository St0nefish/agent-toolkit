#!/usr/bin/env bash
# permission-manager-wrapper.sh — Test wrapper for Crush permission integration
# Usage: ./permission-manager-wrapper.sh <command> <description>

set -euo pipefail

# Log inputs to a file for debugging
LOG_FILE="${PERMISSION_LOG_FILE:-${HOME}/.claude/permission-manager-test.log}"

mkdir -p "$(dirname "$LOG_FILE")"
{
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "Command: $1"
  echo "Description: $2"
  echo "WorkingDir: ${3:-$PWD}"
  echo ""
} >> "$LOG_FILE"

# Hard-coded test decisions (replace these with real classifier later)
case "$1" in
  *"| grep "*)
    echo "ask"
    ;;
  *"git push"*)
    echo "deny"
    ;;
  *"ls "*|*"cat "*|*"grep "*)
    echo "allow"
    ;;
  *)
    echo "ask"
    ;;
esac