#!/usr/bin/env bash
# hook-compat.sh — Normalize Claude Code / Copilot CLI hook payloads.
#
# Source this file after reading stdin into HOOK_INPUT:
#
#   HOOK_INPUT=$(cat)
#   # shellcheck source=scripts/hook-compat.sh
#   source "$(dirname "$0")/hook-compat.sh"
#
# Exports (always set, may be empty):
#   HOOK_FORMAT          — "claude" or "copilot"
#   HOOK_TOOL_NAME       — PascalCase tool name (e.g. "Bash", "Edit", "Write")
#   HOOK_COMMAND         — bash command for PreToolUse/Bash hooks
#   HOOK_FILE_PATH       — file path for PostToolUse/Edit/Write hooks
#   HOOK_EVENT_NAME      — hook event (e.g. "UserPromptSubmit", "Stop")
#   HOOK_PERMISSION_MODE — "default" or "bypassPermissions"
#                          Claude Code: from payload field permission_mode
#                          Copilot CLI: from COPILOT_ALLOW_ALL env var (--allow-all / --yolo)
#
# Functions (PreToolUse hooks only):
#   hook_ask REASON    — output "ask" decision (Claude) / "deny" (Copilot — no "ask" equivalent)
#   hook_allow REASON  — output "allow" decision
#   hook_deny REASON   — output hard "deny" decision on both CLIs (always blocks)

# --- Format detection ---
if echo "$HOOK_INPUT" | jq -e '.toolName' >/dev/null 2>&1; then
  HOOK_FORMAT="copilot"
else
  HOOK_FORMAT="claude"
fi

# --- Tool name (normalized to PascalCase) ---
if [[ "$HOOK_FORMAT" == "copilot" ]]; then
  _hook_raw_tool=$(echo "$HOOK_INPUT" | jq -r '.toolName // empty')
  HOOK_TOOL_NAME="${_hook_raw_tool^}"
else
  HOOK_TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty')
fi

# --- Bash command (PreToolUse) ---
if [[ "$HOOK_FORMAT" == "copilot" ]]; then
  HOOK_COMMAND=$(echo "$HOOK_INPUT" | jq -r 'try (.toolArgs | fromjson | .command) catch ""' 2>/dev/null || echo "")
else
  HOOK_COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')
fi

# --- File path (PostToolUse) ---
if [[ "$HOOK_FORMAT" == "copilot" ]]; then
  HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | jq -r 'try (.toolArgs | fromjson | .file_path) catch ""' 2>/dev/null || echo "")
else
  HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')
fi

# --- Hook event name ---
HOOK_EVENT_NAME=$(echo "$HOOK_INPUT" | jq -r '.hook_event_name // empty')
# Copilot CLI omits hook_event_name; hooks.json entries pass it via env var instead
if [[ -z "$HOOK_EVENT_NAME" ]] && [[ -n "${HOOK_EVENT_OVERRIDE:-}" ]]; then
  HOOK_EVENT_NAME="$HOOK_EVENT_OVERRIDE"
fi

# --- Permission mode ---
# Unified detection of "allow all" mode across both CLIs.
if [[ "$HOOK_FORMAT" == "copilot" ]]; then
  if [[ "${COPILOT_ALLOW_ALL:-}" == "true" ]]; then
    HOOK_PERMISSION_MODE="bypassPermissions"
  else
    HOOK_PERMISSION_MODE="default"
  fi
else
  HOOK_PERMISSION_MODE=$(echo "$HOOK_INPUT" | jq -r '.permission_mode // "default"')
fi

# --- Permission decision helpers (PreToolUse hooks only) ---

# Output an "ask" decision (Claude Code prompts the user) or "deny" (Copilot CLI — no "ask"
# equivalent; user must run the command manually if intended)
hook_ask() {
  local reason="$1"
  if [[ "$HOOK_FORMAT" == "copilot" ]]; then
    jq -n --arg r "$reason" '{"permissionDecision":"deny","permissionDecisionReason":$r}'
  else
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  fi
}

# Output an "allow" decision
hook_allow() {
  local reason="$1"
  if [[ "$HOOK_FORMAT" == "copilot" ]]; then
    jq -n --arg r "$reason" '{"permissionDecision":"allow","permissionDecisionReason":$r}'
  else
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
  fi
}

# Output a hard "deny" decision — blocks on both CLIs with no override path.
# Use for genuinely destructive patterns (redirection, find -delete, etc.).
hook_deny() {
  local reason="$1"
  if [[ "$HOOK_FORMAT" == "copilot" ]]; then
    jq -n --arg r "$reason" '{"permissionDecision":"deny","permissionDecisionReason":$r}'
  else
    jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  fi
}
