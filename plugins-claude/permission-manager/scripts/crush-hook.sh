#!/usr/bin/env bash
# Crush PreToolUse hook for agent-toolkit permission management
# Usage: Add to crush.json hooks section

set -euo pipefail

# Environment variables set by Crush:
# CRUSH_EVENT - Event name (PreToolUse)
# CRUSH_TOOL_NAME - Tool being called (Bash, Edit, etc.)
# CRUSH_TOOL_INPUT_COMMAND - The command string (for Bash tool)
# CRUSH_TOOL_INPUT_FILE_PATH - File path (for Edit tool)
# CRUSH_SESSION_ID - Session ID
# CRUSH_CWD - Current working directory

# Log inputs for debugging
LOG_FILE="${PERMISSION_LOG_FILE:-${HOME}/.claude/permission-manager-test.log}"
mkdir -p "$(dirname "$LOG_FILE")"
{
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "Event: $CRUSH_EVENT"
  echo "Tool: $CRUSH_TOOL_NAME"
  echo "Command: ${CRUSH_TOOL_INPUT_COMMAND:-N/A}"
  echo "CWD: $CRUSH_CWD"
  echo ""
} >>"$LOG_FILE"

# For bash tools, run our classifier
if [[ "$CRUSH_TOOL_NAME" == "Bash" ]]; then
  COMMAND="$CRUSH_TOOL_INPUT_COMMAND"

  # Run the test wrapper (will be replaced with real cmd-gate later)
  decision=$("$(dirname "$0")/crush-wrapper.sh" "$COMMAND" "Crush hook" "$CRUSH_CWD")

  # Output decision in Crush format
  case "$decision" in
    allow)
      echo '{"decision":"allow","reason":"agent-toolkit: allow"}'
      ;;
    deny)
      echo '{"decision":"deny","reason":"agent-toolkit: deny"}'
      ;;
    ask)
      echo '{"decision":"ask","reason":"agent-toolkit: ask"}'
      ;;
    *)
      echo '{"decision":"none"}'
      ;;
  esac
  exit 0
fi

# For non-bash tools, pass through (no opinion)
echo '{"decision":"none"}'
