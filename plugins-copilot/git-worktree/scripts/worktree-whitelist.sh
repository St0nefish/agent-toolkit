#!/usr/bin/env bash
# worktree-whitelist.sh — PreToolUse hook for the git-worktree plugin.
#
# Auto-allows:
#   1. All git worktree management commands (add, remove, prune, move, lock, unlock, repair)
#   2. Bash commands that reference a registered worktree path
#   3. Edit/Write file operations targeting a registered worktree path
#
# Falls through (exit 0, no output) for everything else.

set -euo pipefail

HOOK_INPUT=$(cat)
SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=hook-compat.sh
source "$SCRIPTS_DIR/hook-compat.sh"
# shellcheck source=worktree-lib.sh
source "$SCRIPTS_DIR/worktree-lib.sh"

# Only act on Bash, Edit, Write, and MultiEdit tool calls
case "$HOOK_TOOL_NAME" in
  Bash | Edit | Write | MultiEdit) ;;
  *) exit 0 ;;
esac

# --- Helper: check if a command is a git worktree management command ---
# Returns 0 (match) and sets WT_SUBCMD if so.
is_git_worktree_cmd() {
  local cmd="$1"
  # Match: git [global-flags] worktree <subcmd>
  if echo "$cmd" | perl -ne 'exit 1 unless /^\s*git(\s+\S+)*\s+worktree\s+\S/; exit 0' 2>/dev/null; then
    # Extract the worktree subcommand
    WT_SUBCMD=$(echo "$cmd" | grep -oP '(?<=worktree\s)\S+' | head -1)
    return 0
  fi
  WT_SUBCMD=""
  return 1
}

# --- 1. Git worktree management commands ---
if [[ "$HOOK_TOOL_NAME" == "Bash" && -n "$HOOK_COMMAND" ]]; then
  WT_SUBCMD=""
  if is_git_worktree_cmd "$HOOK_COMMAND"; then
    case "$WT_SUBCMD" in
      add | remove | prune | move | lock | unlock | repair | list)
        hook_allow "git worktree $WT_SUBCMD is a safe worktree management command"
        exit 0
        ;;
    esac
  fi
fi

# --- 2 & 3. Operations targeting a registered worktree path ---
# Skip this check if git isn't available or we're not in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Build list of registered worktree paths (once)
mapfile -t WORKTREE_PATHS < <(list_worktrees | cut -f1)

[[ ${#WORKTREE_PATHS[@]} -eq 0 ]] && exit 0

check_path_in_worktree() {
  local target="$1"
  [[ -z "$target" ]] && return 1
  for wt_path in "${WORKTREE_PATHS[@]}"; do
    [[ -z "$wt_path" ]] && continue
    if [[ "$target" == "$wt_path" || "$target" == "$wt_path/"* ]]; then
      hook_allow "operation targets registered worktree: $wt_path"
      exit 0
    fi
  done
  return 0
}

case "$HOOK_TOOL_NAME" in
  Bash)
    # Check if the command string contains a worktree path
    for wt_path in "${WORKTREE_PATHS[@]}"; do
      [[ -z "$wt_path" ]] && continue
      if [[ "$HOOK_COMMAND" == *"$wt_path"* ]]; then
        hook_allow "bash command references registered worktree: $wt_path"
        exit 0
      fi
    done
    ;;
  Edit | Write | MultiEdit)
    check_path_in_worktree "$HOOK_FILE_PATH"
    ;;
esac

# No match — fall through to other hooks / Copilot's built-in permissions
exit 0
