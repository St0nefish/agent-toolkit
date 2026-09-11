#!/usr/bin/env bash
# approve-own-scripts.sh — PreToolUse hook to auto-approve a plugin's own files.
#
# Two jobs, by tool:
#   Bash             — auto-allow any command whose executable lives under the
#                      plugin's scripts/ directory (and guard outward PR publish).
#   Read|Glob|Grep   — auto-allow reading any file under the plugin's own root.
#                      Plugins live in an out-of-workspace install cache, so a
#                      skill that Reads its own ${CLAUDE_PLUGIN_ROOT}/reference/*
#                      otherwise prompts the user on every invocation.
#
# Falls through (exit 0, no output) for anything that doesn't match, letting
# other hooks or the user decide.
#
# Claude Code hooks.json — register for both tool groups:
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [{
#             "type": "command",
#             "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/approve-own-scripts.sh"
#           }]
#         },
#         {
#           "matcher": "Read|Glob|Grep",
#           "hooks": [{
#             "type": "command",
#             "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/approve-own-scripts.sh"
#           }]
#         }
#       ]
#     }
#   }
#
# Copilot CLI hooks.json (preToolUse has no matcher — the script self-filters
# by tool name, so a single entry covers both groups):
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

# CLAUDE_PLUGIN_ROOT (Claude Code) or COPILOT_PLUGIN_ROOT (Copilot CLI) is set
# to the installed plugin directory. If neither is set, we can't determine
# which files belong to this plugin. We resolve it here but DON'T exit yet:
# the Bash PR-publish guard below must fire even when the root is unknown.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${COPILOT_PLUGIN_ROOT:-}}"

# --- Read/Glob/Grep: auto-approve reads of this plugin's own bundled files ---
# Read carries the target in file_path; Glob/Grep use path. Pull whichever is
# present directly from the payload — `// empty` collapses both "missing key"
# and JSON null so a pathless Grep yields an empty string (we don't lean on
# HOOK_FILE_PATH here: its copilot path renders a missing key as "null").
if [[ "$HOOK_TOOL_NAME" == "Read" || "$HOOK_TOOL_NAME" == "Glob" || "$HOOK_TOOL_NAME" == "Grep" ]]; then
  # Without a plugin root we can't tell which files are "ours" — defer.
  [[ -n "$PLUGIN_ROOT" ]] || exit 0
  if [[ "$HOOK_FORMAT" == "copilot" ]]; then
    read_target=$(echo "$HOOK_INPUT" | jq -r 'try ((.toolArgs | fromjson) | (.file_path // .path // empty)) catch empty' 2>/dev/null || echo "")
  else
    read_target=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
  fi
  # Empty target (e.g. a project-wide Grep with no path) or traversal: defer.
  [[ -n "$read_target" && "$read_target" != *".."* ]] || exit 0
  if [[ "$read_target" == "${PLUGIN_ROOT}/"* ]]; then
    hook_allow "plugin file: ${read_target#"${PLUGIN_ROOT}/"}"
  fi
  exit 0
fi

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0

# --- Outward VCS publish guard (applies to ALL Bash, not just own scripts) ---
# Never SILENTLY approve creating or merging a pull request. Publishing/merging
# a PR triggers CI and any auto-merge automation, so it must be confirmed by the
# user rather than waved through. We require BOTH a known VCS CLI token
# (gh / tea) AND a "pr create" | "pr merge" subcommand, so read-only forms and
# reversible ones (`pr close`) still fall through. On Copilot CLI, hook_ask
# degrades to a hard deny (there is no "ask" there) — meaning the user simply
# runs the publish step manually.
#
# `git-wait` is deliberately absent from the token list: it only ever waits on a
# PR or a CI run and has no create/merge surface to guard.
#
# Enabling auto-merge is covered: the real path is `gh pr merge --auto`, which
# the `pr merge` arm already catches. We deliberately do NOT broaden to a bare
# "auto-merge" token — that would trap read-only status probes. (`pr review
# --approve`, `release create` etc. are out of scope by design — this guard is
# narrowly about opening/merging a PR.)
if [[ "$HOOK_COMMAND" =~ (^|[[:space:]/])(gh|tea)[[:space:]] ]] &&
  [[ "$HOOK_COMMAND" =~ (^|[[:space:]])pr[[:space:]]+(create|merge)([[:space:]]|$) ]]; then
  # NOTE: BASH_REMATCH below reflects the SECOND [[ =~ ]] (the pr subcommand
  # test, evaluated last), so [2] is "create"|"merge". Do not reorder the two
  # conditions — swapping them would make this message read "pr gh"/"pr tea".
  hook_ask "Confirm before publishing: this opens/merges a PR (\`pr ${BASH_REMATCH[2]}\`), which triggers CI and auto-merge. Session flows must stop for your review first — approve only if you intend to publish right now."
  exit 0
fi

# The scripts-dir match below needs a known plugin root; the VCS guard above
# did not. Defer now if we still don't have one.
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
