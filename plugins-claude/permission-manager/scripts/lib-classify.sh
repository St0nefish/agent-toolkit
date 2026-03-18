#!/usr/bin/env bash
# lib-classify.sh — Decision helpers, parsing, custom patterns, and dispatch.
# Sourced by cmd-gate.sh after hook-compat.sh and shfmt Op code probing.

# shellcheck source=hook-compat.sh

# --- Decision helpers ---
# In segment mode (SEGMENT_MODE=1), set globals and return.
# In direct mode (default), output JSON and exit.
SEGMENT_MODE=0
CLASSIFY_RESULT=0 # 0=allow, 1=ask, 2=deny
CLASSIFY_REASON=""
CLASSIFY_MATCHED=0 # 1 if any classifier made a decision

ask() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=1
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_ask "$1"
  exit 0
}

allow() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=0
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_allow "$1"
  exit 0
}

deny() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=2
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_deny "$1"
  exit 0
}

# --- Compound command parsing via shfmt ---

# Extract all simple commands from a compound command string using shfmt's AST.
# Outputs one command per line.
parse_segments() {
  printf '%s' "$1" | shfmt --tojson 2>/dev/null | jq -r '
    def extract_cmds:
      if .Cmd?.Type? == "BinaryCmd" then
        (.Cmd.X | extract_cmds), (.Cmd.Y | extract_cmds)
      elif .Cmd?.Type? == "CallExpr" then
        [.Cmd.Args[]? | [.Parts[]? | select(.Type? == "Lit") | .Value] | join("")] | join(" ")
      elif type == "object" then
        if .Cmd? then .Cmd | extract_cmds else empty end
      else empty end;
    .Stmts[]? | extract_cmds
  ' 2>/dev/null
}

# Check for output redirections using shfmt AST.
# Must run on the FULL original command (before segment extraction),
# since parse_segments strips redirections from extracted segments.
check_redirections_ast() {
  local cmd="$1"
  local has_redir
  has_redir=$(printf '%s' "$cmd" | shfmt --tojson 2>/dev/null | jq \
    --argjson op_gt "$SHFMT_OP_GT" --argjson op_append "$SHFMT_OP_APPEND" '
    [.. | objects | select(.Redirs?) | .Redirs[]
     | select(.Op == $op_gt or .Op == $op_append)
     # Allow stderr redirects (N.Value == "2")
     | select((.N?.Value? // "") != "2")
     # Allow redirects to /dev/null (harmless output discard)
     | select(([.Word?.Parts[]? | select(.Type? == "Lit") | .Value] | join("")) != "/dev/null")
     # Allow redirects to /tmp/ (scratch space, no persistent side-effects)
     | select(([.Word?.Parts[]? | select(.Type? == "Lit") | .Value] | join("")) | startswith("/tmp/") | not)
    ] | length
  ' 2>/dev/null || echo "0")
  # Op codes probed at startup (SHFMT_OP_GT / SHFMT_OP_APPEND)
  # Excluded: stderr redirects (2>), redirects to /dev/null, and redirects to /tmp/
  if [[ "$has_redir" -gt 0 ]]; then
    deny "Command contains output redirection (> or >>)"
  fi
}

# --- Custom command patterns ---
# Load user-defined allow-list globs from global and project config files.
# Patterns are matched per-segment via bash glob: [[ "$command" == $pattern ]]
# Override paths via env vars for testing:
#   COMMAND_PERMISSIONS_GLOBAL  — default: ~/.claude/command-permissions.json
#   COMMAND_PERMISSIONS_PROJECT — default: .claude/command-permissions.json
CUSTOM_ALLOW_PATTERNS=()

load_custom_patterns() {
  local global_file="${COMMAND_PERMISSIONS_GLOBAL:-${HOME}/.claude/command-permissions.json}"
  local project_file="${COMMAND_PERMISSIONS_PROJECT:-.claude/command-permissions.json}"
  for f in "$global_file" "$project_file"; do
    if [[ -f "$f" ]]; then
      local _p
      mapfile -t _p < <(jq -r '.allow[]? // empty' "$f" 2>/dev/null)
      CUSTOM_ALLOW_PATTERNS+=("${_p[@]+"${_p[@]}"}")
    fi
  done
}

check_custom_patterns() {
  for pattern in "${CUSTOM_ALLOW_PATTERNS[@]+"${CUSTOM_ALLOW_PATTERNS[@]}"}"; do
    # shellcheck disable=SC2254
    if [[ "$command" == $pattern ]]; then
      allow "custom pattern: $pattern"
      return 0
    fi
  done
}

# --- Classify a single command segment ---
# Sets CLASSIFY_RESULT (0=allow, 1=ask, 2=deny) and CLASSIFY_REASON.
classify_single_command() {
  local command="$1" # shadows the global for classifier reuse
  CLASSIFY_RESULT=0
  CLASSIFY_REASON=""
  CLASSIFY_MATCHED=0

  # Run classifiers — each may call allow/ask/deny which sets CLASSIFY_MATCHED
  check_custom_patterns
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_find
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_read_only_tools
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_git
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_gradle
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_gh
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_tea
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_docker
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_npm
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_pip
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_cargo
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_jvm_tools
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  # No classifier matched — passthrough to Claude Code's built-in permission system
  return 0
}
