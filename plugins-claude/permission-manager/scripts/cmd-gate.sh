#!/usr/bin/env bash
# cmd-gate.sh — PreToolUse hook for Bash command allow/ask/deny gating.
# Single authority for all Bash command permissions across Claude Code and Copilot CLI.
#
# Uses shfmt --tojson to parse compound commands into individual segments,
# then classifies each segment independently. The most restrictive result wins:
#   deny > ask > allow
#
# Classification buckets:
#   allow — read-only command; auto-approved on both CLIs.
#   ask   — write/modifying command; prompts user on Claude Code.
#           (Copilot CLI has no "ask" — falls through with no opinion.)
#   deny  — genuinely destructive pattern; hard-blocked everywhere.
#
# Classifiers cover:
#   bash-read / system — cat, grep, ls, ps, df, echo, printf, etc.
#   git               — read-only subcommands allow; write subcommands ask
#   gradle / jvm      — reporting + local build/test allow; publish/deploy ask
#   github (gh)       — list/view/status allow; create/merge/edit ask
#   docker            — ps/logs/inspect allow; run/build/exec ask
#   npm / node        — list/audit/version + install/test/run allow; publish ask
#   pip / python      — list/show/freeze + install allow; uninstall ask
#   cargo / rust      — version/check + build/test/clippy/fmt allow; run/publish ask

set -euo pipefail

# Hooks (especially Copilot CLI) may be spawned with a restricted PATH.
# If shfmt isn't found, probe common user-local install locations and add the first match.
if ! command -v shfmt &>/dev/null; then
  for _d in "$HOME/.local/bin" "$HOME/go/bin" "$HOME/bin" "/usr/local/bin"; do
    if [[ -x "$_d/shfmt" ]]; then
      PATH="$_d:$PATH"
      break
    fi
  done
  unset _d
fi

HOOK_INPUT=$(cat)
# shellcheck source=scripts/hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0
command="$HOOK_COMMAND"
[[ -n "$command" ]] || exit 0

# --- Bypass permissions mode ---
# When the user has opted into unrestricted execution, skip classification entirely.
# Claude Code: --dangerously-skip-permissions; Copilot CLI: --allow-all / --yolo
if [[ "$HOOK_PERMISSION_MODE" == "bypassPermissions" ]]; then
  exit 0
fi

# --- Allow-edit mode detection ---
# In allow-edits mode, Claude Code auto-approves file edits. We promote safe
# project-local writes (chmod, ln, mkdir, etc.) to auto-allow as well.
ALLOW_EDIT_ACTIVE=0
if [[ "$HOOK_PERMISSION_MODE" == "acceptEdits" ]]; then
  ALLOW_EDIT_ACTIVE=1
fi
export ALLOW_EDIT_ACTIVE

# --- Dependency check ---
# shfmt and jq are hard requirements for compound command parsing.
# If missing, deny all Bash commands with a clear install message.
check_dependencies() {
  local missing=()
  command -v shfmt &>/dev/null || missing+=("shfmt")
  command -v jq &>/dev/null || missing+=("jq")
  if [[ ${#missing[@]} -gt 0 ]]; then
    hook_deny "cmd-gate: missing required dependencies: ${missing[*]}. Run /permissions setup to install."
    exit 0
  fi
}

check_dependencies

# --- Probe shfmt redirect Op codes ---
# shfmt's AST Op values are internal Go iota constants that shift between
# releases (e.g. > was 54 in v3.7, became 63 in v3.13). Rather than
# hardcoding values, probe them once at startup with known redirect patterns.
SHFMT_OP_GT=$(printf '%s' 'x > /tmp/x' | shfmt --tojson 2>/dev/null |
  jq '.. | objects | select(.Redirs?) | .Redirs[0].Op' 2>/dev/null || echo "")
SHFMT_OP_APPEND=$(printf '%s' 'x >> /tmp/x' | shfmt --tojson 2>/dev/null |
  jq '.. | objects | select(.Redirs?) | .Redirs[0].Op' 2>/dev/null || echo "")

if [[ -z "$SHFMT_OP_GT" || -z "$SHFMT_OP_APPEND" ]]; then
  hook_deny "cmd-gate: failed to probe shfmt redirect Op codes — cannot safely classify commands"
  exit 0
fi

# --- Source library and classifiers ---
SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=lib-classify.sh
source "$SCRIPTS_DIR/lib-classify.sh"
for _clf in "$SCRIPTS_DIR/classifiers/"*.sh; do
  # shellcheck disable=SC1090
  source "$_clf"
done
unset _clf

load_custom_patterns
load_allow_edit_commands

# --- Audit logging ---
# Append ask/deny decisions to a JSONL log for learn.sh to analyze.
# Log location: ~/.claude/permission-audit.jsonl (override via $PERMISSION_AUDIT_LOG)
log_decision() {
  local decision="$1" reason="$2" cmd="$3"
  local log_file="${PERMISSION_AUDIT_LOG:-${HOME}/.claude/permission-audit.jsonl}"
  local project mode
  project=$(basename "$PWD")
  if [[ "${ALLOW_EDIT_ACTIVE:-0}" -eq 1 ]]; then
    mode="allow-edit"
  else
    mode="default"
  fi
  mkdir -p "$(dirname "$log_file")"
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg command "$cmd" \
    --arg decision "$decision" \
    --arg reason "$reason" \
    --arg mode "$mode" \
    --arg project "$project" \
    --arg cwd "$PWD" \
    '{ts:$ts,command:$command,decision:$decision,reason:$reason,mode:$mode,project:$project,cwd:$cwd}' \
    >>"$log_file"
}

# --- Main entry ---
# Parse compound commands into segments, classify each, take most restrictive result.
main() {
  # Check redirections on the FULL original command before segmentation,
  # since parse_segments strips redirections from extracted segments.
  SEGMENT_MODE=1
  check_redirections_ast "$command"
  if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
    SEGMENT_MODE=0
    log_decision "deny" "$CLASSIFY_REASON" "$command"
    hook_deny "$CLASSIFY_REASON"
    exit 0
  fi

  local segments
  segments=$(parse_segments "$command")

  # If shfmt fails to parse (e.g. incomplete command), fall back to single-command mode
  if [[ -z "$segments" ]]; then
    segments="$command"
  fi

  local worst=0 worst_reason="" any_classified=0 any_unclassified=0

  while IFS= read -r segment; do
    [[ -z "$segment" ]] && continue
    segment=$(echo "$segment" | sed 's/^ *//; s/ *$//')
    [[ -z "$segment" ]] && continue

    classify_single_command "$segment"
    if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
      any_classified=1
      if ((CLASSIFY_RESULT > worst)); then
        worst=$CLASSIFY_RESULT
        worst_reason="$CLASSIFY_REASON"
      elif [[ -z "$worst_reason" && -n "$CLASSIFY_REASON" ]]; then
        worst_reason="$CLASSIFY_REASON"
      fi
    else
      ((any_unclassified++)) || true
    fi
  done <<<"$segments"

  SEGMENT_MODE=0

  # No classifier had an opinion — passthrough to Claude Code's built-in permissions
  if [[ "$any_classified" -eq 0 ]]; then
    exit 0
  fi

  # If any segment was unclassified and worst is allow/ask, passthrough
  # to let Claude Code's built-in permissions handle the unknown commands.
  # Deny verdicts still block regardless.
  if [[ "$any_unclassified" -gt 0 && "$worst" -le 1 ]]; then
    exit 0
  fi

  case $worst in
    0)
      log_decision "allow" "$worst_reason" "$command"
      hook_allow "$worst_reason"
      exit 0
      ;;
    1)
      log_decision "ask" "$worst_reason" "$command"
      if [[ "$HOOK_FORMAT" == "claude" ]]; then
        hook_ask "$worst_reason"
        exit 0
      fi
      # Copilot CLI: no ask equivalent — passthrough (let Copilot's own permissions handle it)
      exit 0
      ;;
    2)
      log_decision "deny" "$worst_reason" "$command"
      hook_deny "$worst_reason"
      exit 0
      ;;
  esac
}

main
