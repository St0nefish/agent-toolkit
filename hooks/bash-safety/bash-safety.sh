#!/usr/bin/env bash
# bash-safety.sh — PreToolUse hook for auto-approved Bash commands.
# Forces a user prompt (not hard-block) for:
#   1. Shell output redirection (> or >>) in any command
#   2. Destructive find operations (-delete, unsafe -exec/-execdir/-ok/-okdir)
#
# Uses permissionDecision:"ask" so the user can still approve if intended.

set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n "$command" ]] || exit 0

# Output an "ask" decision — forces the user to confirm instead of auto-approving.
ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- Shell output redirection ---
# Catches > and >> but not fd duplication (2>&1, >&2) or process substitution >(...)
# Strip heredoc bodies first to avoid false positives on > inside string content
# (e.g., <noreply@anthropic.com> in Co-Authored-By lines)
stripped=$(printf '%s' "$command" | perl -0777 -pe 's/<<[-~]?\\?\x27?(\w+)\x27?[^\n]*\n.*?\n\1(\n|$)/\n/gs')
if echo "$stripped" | grep -qP '(?<![0-9&])>{1,2}(?![>&(])'; then
  ask "Command contains output redirection (> or >>)"
fi

# --- Destructive find operations ---
if echo "$command" | grep -qP '^\s*find\s'; then
  # -delete is always destructive
  if echo "$command" | grep -qP '\s-delete\b'; then
    ask "find -delete can remove files"
  fi

  # -exec/-execdir/-ok/-okdir: allow known read-only commands, prompt for others
  if echo "$command" | grep -qP '\s-(exec|execdir|ok|okdir)\s'; then
    unsafe=$(echo "$command" \
      | grep -oP '-(exec|execdir|ok|okdir)\s+\K\S+' \
      | while read -r cmd; do
          base=$(basename "$cmd" 2>/dev/null || echo "$cmd")
          case "$base" in
            grep|egrep|fgrep|rg|cat|head|tail|less|more|file|stat|ls|wc|jq|\
            sort|uniq|cut|tr|strings|xxd|od|hexdump|md5sum|sha256sum|sha1sum|\
            readlink|realpath|basename|dirname|test|\[)
              ;; # read-only, safe
            *)
              echo "$base"
              ;;
          esac
        done)
    if [[ -n "$unsafe" ]]; then
      ask "find -exec with '$(echo "$unsafe" | head -1)' is not in the read-only safe list"
    fi
  fi
fi

exit 0
