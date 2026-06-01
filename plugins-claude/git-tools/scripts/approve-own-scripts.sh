#!/usr/bin/env bash
# approve-own-scripts.sh — PreToolUse hook to auto-approve a plugin's own scripts.
#
# Place in a plugin's hooks.json as a PreToolUse hook for Bash.
# Auto-allows any Bash command whose executable path starts with the
# plugin's scripts/ directory. Falls through (exit 0, no output) for
# commands that don't match, letting other hooks or the user decide.
#
# Claude Code hooks.json:
#   {
#     "hooks": {
#       "PreToolUse": [{
#         "matcher": "Bash",
#         "hooks": [{
#           "type": "command",
#           "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/approve-own-scripts.sh"
#         }]
#       }]
#     }
#   }
#
# Copilot CLI hooks.json:
#   {
#     "version": 1,
#     "hooks": {
#       "preToolUse": [{
#         "type": "command",
#         "bash": "bash ${COPILOT_PLUGIN_ROOT}/scripts/approve-own-scripts.sh"
#       }]
#     }
#   }

set -euo pipefail

HOOK_INPUT=$(cat)
# shellcheck source=hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0

# --- Outward VCS publish guard (applies to ALL Bash, not just own scripts) ---
# Never SILENTLY approve creating or merging a pull request — whether it goes
# through this plugin's git-cli wrapper OR a direct `gh`/`tea` invocation that
# would otherwise sidestep the wrapper (and likely hit a user allowlist).
# Publishing/merging a PR triggers CI and any auto-merge automation, so it must
# be confirmed by the user rather than waved through. We require BOTH a known
# VCS CLI token (gh / tea / git-cli) AND a "pr create" | "pr merge" subcommand,
# so read-only forms (`pr auto-merge-status`) and reversible ones (`pr close`)
# still fall through. On Copilot CLI, hook_ask degrades to a hard deny (there is
# no "ask" there) — meaning the user simply runs the publish step manually.
#
# Enabling auto-merge is covered: the real path is `gh pr merge --auto`, which
# the `pr merge` arm already catches. We deliberately do NOT broaden to a bare
# "auto-merge" token — that would also trap the read-only `pr auto-merge-status`
# call the session-end flow relies on. (`pr review --approve`, `release create`
# etc. are out of scope by design — this guard is narrowly about opening/merging
# a PR.)
if [[ "$HOOK_COMMAND" =~ (^|[[:space:]/])(gh|tea|git-cli)[[:space:]] ]] &&
  [[ "$HOOK_COMMAND" =~ (^|[[:space:]])pr[[:space:]]+(create|merge)([[:space:]]|$) ]]; then
  # NOTE: BASH_REMATCH below reflects the SECOND [[ =~ ]] (the pr subcommand
  # test, evaluated last), so [2] is "create"|"merge". Do not reorder the two
  # conditions — swapping them would make this message read "pr gh"/"pr tea".
  hook_ask "Confirm before publishing: this opens/merges a PR (\`pr ${BASH_REMATCH[2]}\`), which triggers CI and auto-merge. Session flows must stop for your review first — approve only if you intend to publish right now."
  exit 0
fi

# CLAUDE_PLUGIN_ROOT (Claude Code) or COPILOT_PLUGIN_ROOT (Copilot CLI) is set
# to the installed plugin directory. If neither is set, we can't determine
# which scripts belong to this plugin.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${COPILOT_PLUGIN_ROOT:-}}"
[[ -n "$PLUGIN_ROOT" ]] || exit 0

SCRIPTS_DIR="${PLUGIN_ROOT}/scripts"

# Check if the command invokes a script from this plugin's scripts/ directory.
# Handles both direct execution (/path/to/scripts/foo ...) and via bash/sh
# (bash /path/to/scripts/foo ...).
cmd="$HOOK_COMMAND"

# Strip leading bash/sh interpreter if present
cmd_path="$cmd"
if [[ "$cmd_path" =~ ^(bash|sh)[[:space:]]+(.*) ]]; then
  cmd_path="${BASH_REMATCH[2]}"
fi

# Extract just the executable path (first token)
read -r exec_path _ <<<"$cmd_path"

# Reject path traversal attempts
if [[ "$exec_path" == *".."* ]]; then
  exit 0
fi

# Match against this plugin's scripts directory
if [[ "$exec_path" == "${SCRIPTS_DIR}/"* ]]; then
  hook_allow "plugin script: ${exec_path#"${SCRIPTS_DIR}/"}"
  exit 0
fi

# No match — fall through to other hooks / user prompt
exit 0
