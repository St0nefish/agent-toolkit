#!/usr/bin/env bash
# notify-on-stop — Desktop notification when Claude finishes a long-running task.
#
# Hooks: UserPromptSubmit (records start time), Stop (fires notification).
# Env:   CLAUDE_NOTIFY_MIN_SECONDS — threshold in seconds (default: 30)

set -euo pipefail

MIN_SECONDS="${CLAUDE_NOTIFY_MIN_SECONDS:-30}"

# Read hook payload from stdin
input="$(cat)"
hook_event="$(echo "$input" | jq -r '.hook_event_name // empty')"

# Derive a stable state file from session_id (fall back to PPID)
session_id="$(echo "$input" | jq -r '.session_id // empty')"
state_file="/tmp/claude-notify-${session_id:-$$}"

# --- UserPromptSubmit: record start epoch -----------------------------------
if [[ "$hook_event" == "UserPromptSubmit" ]]; then
  date +%s > "$state_file"
  exit 0
fi

# --- Stop: maybe fire notification ------------------------------------------
if [[ "$hook_event" == "Stop" ]]; then
  # Avoid loops if we somehow trigger ourselves
  stop_hook_active="$(echo "$input" | jq -r '.stop_hook_active // false')"
  if [[ "$stop_hook_active" == "true" ]]; then
    exit 0
  fi

  # No state file → nothing to do
  if [[ ! -f "$state_file" ]]; then
    exit 0
  fi

  start_epoch="$(cat "$state_file")"
  now_epoch="$(date +%s)"
  elapsed=$(( now_epoch - start_epoch ))

  # Below threshold → exit silently
  if (( elapsed < MIN_SECONDS )); then
    rm -f "$state_file"
    exit 0
  fi

  # Build notification body
  cwd="$(echo "$input" | jq -r '.cwd // empty')"
  project_name="$(basename "${cwd:-unknown}")"
  last_message="$(echo "$input" | jq -r '.last_assistant_message // "" | .[0:100]')"
  body="${project_name}: ${last_message:-Task complete}"

  # Platform dispatch
  if [[ "$(uname)" == "Darwin" ]]; then
    osascript -e "display notification \"$body\" with title \"Claude Code\"" 2>/dev/null || true
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    # WSL — try notify-send (WSLg) first, fall back to PowerShell toast
    if command -v notify-send &>/dev/null; then
      notify-send -a "Claude Code" "Task complete" "$body" 2>/dev/null || true
    else
      powershell.exe -NoProfile -Command "
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
        \$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        \$xml.LoadXml('<toast><visual><binding template=\"ToastText02\"><text id=\"1\">Claude Code</text><text id=\"2\">$body</text></binding></visual></toast>')
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show([Windows.UI.Notifications.ToastNotification]::new(\$xml))
      " 2>/dev/null || true
    fi
  else
    # Native Linux (KDE, GNOME, etc.)
    notify-send -a "Claude Code" "Task complete" "$body" 2>/dev/null || true
  fi

  rm -f "$state_file"
  exit 0
fi

# Unknown event — ignore
exit 0
