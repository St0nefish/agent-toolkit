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
    def part_value:
      if .Type? == "Lit" then .Value
      elif .Type? == "SglQuoted" then .Value
      elif .Type? == "DblQuoted" then ([.Parts[]? | part_value] | join(""))
      else "" end;
    def extract_cmds:
      if .Cmd?.Type? == "BinaryCmd" then
        (.Cmd.X | extract_cmds), (.Cmd.Y | extract_cmds)
      elif .Cmd?.Type? == "CallExpr" then
        [.Cmd.Args[]? | [.Parts[]? | part_value] | join("")] | join(" ")
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

# --- Allow-edit command list ---
# Commands promoted to "allow" in allow-edits mode.
# Loaded from allow-edit-permissions.json (global + project), falling back to built-in defaults.
# Override paths via env vars for testing:
#   ALLOW_EDIT_PERMISSIONS_GLOBAL  — default: ~/.claude/allow-edit-permissions.json
#   ALLOW_EDIT_PERMISSIONS_PROJECT — default: .claude/allow-edit-permissions.json
ALLOW_EDIT_COMMANDS=()
ALLOW_EDIT_DEFAULTS=(chmod ln mkdir cp mv touch install tee)

load_allow_edit_commands() {
  local global_file="${ALLOW_EDIT_PERMISSIONS_GLOBAL:-${HOME}/.claude/allow-edit-permissions.json}"
  local project_file="${ALLOW_EDIT_PERMISSIONS_PROJECT:-.claude/allow-edit-permissions.json}"
  local any_file_found=false
  for f in "$global_file" "$project_file"; do
    if [[ -f "$f" ]]; then
      any_file_found=true
      local _p
      mapfile -t _p < <(jq -r '.allow[]? // empty' "$f" 2>/dev/null)
      ALLOW_EDIT_COMMANDS+=("${_p[@]+"${_p[@]}"}")
    fi
  done
  if [[ "$any_file_found" == false ]]; then
    ALLOW_EDIT_COMMANDS=("${ALLOW_EDIT_DEFAULTS[@]}")
  fi
}

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

# --- Prefix-wrapper stripping ---
# Strips benign launcher/execution-context prefixes from a command segment and
# returns the inner command in STRIPPED_COMMAND (empty if no stripping occurred).
# Handles: sudo [flags], command [flags], env [VAR=val/-flags], nice [-n N],
#          timeout [flags] DURATION, xargs [flags] (single-level only).
# Used by classify_single_command before first-token dispatch.
strip_prefix_wrappers() {
  local seg="$1"
  local -a tokens
  read -ra tokens <<<"$seg"
  local n=${#tokens[@]}
  [[ $n -lt 2 ]] && {
    STRIPPED_COMMAND=""
    return 0
  }

  local first="${tokens[0]}"
  case "$first" in
    sudo)
      # sudo [-flags [-arg]] [--] <cmd...>
      local i=1
      while ((i < n)); do
        case "${tokens[$i]}" in
          --)
            ((i++))
            break
            ;;
          -u | -g | -h | -r | -t | -C | -T | -D | -p | -R | -U)
            ((i += 2)) || true
            ;; # flags consuming next arg
          -*) ((i++)) || true ;;
          *) break ;;
        esac
      done
      if ((i < n)); then
        STRIPPED_COMMAND="${tokens[*]:$i}"
      else
        STRIPPED_COMMAND=""
      fi
      ;;
    command)
      # command [-pvV] [--] <cmd...>
      # command -v/-V PROG is a read-only existence check; handled by check_read_only_tools.
      # command [-p] [--] PROG ARGS is a transparent launcher — strip and re-classify.
      local i=1
      while ((i < n)); do
        case "${tokens[$i]}" in
          -v | -V | -v* | -V*)
            # Existence-check form — leave for check_read_only_tools to allow
            STRIPPED_COMMAND=""
            return 0
            ;;
          --)
            ((i++))
            break
            ;;
          -*) ((i++)) || true ;;
          *) break ;;
        esac
      done
      if ((i < n)); then
        STRIPPED_COMMAND="${tokens[*]:$i}"
      else
        STRIPPED_COMMAND=""
      fi
      ;;
    nice)
      # nice [-n NUM] <cmd...>
      local i=1
      if [[ "${tokens[1]:-}" == "-n" && $n -ge 3 ]]; then
        i=3
      elif [[ "${tokens[1]:-}" == -n[0-9]* ]]; then
        i=2
      fi
      if ((i < n)); then
        STRIPPED_COMMAND="${tokens[*]:$i}"
      else
        STRIPPED_COMMAND=""
      fi
      ;;
    timeout)
      # timeout [--signal=SIG] [--kill-after=D] [-s SIG] [-k D] [--foreground] [--preserve-status] DURATION <cmd...>
      local i=1
      while ((i < n)); do
        case "${tokens[$i]}" in
          --signal=* | --kill-after=* | --preserve-status | --foreground)
            ((i++)) || true
            ;;
          -s | -k)
            ((i += 2)) || true
            ;;
          -*)
            ((i++)) || true
            ;;
          *)
            # This token is the DURATION — skip it, rest is <cmd...>
            ((i++)) || true
            break
            ;;
        esac
      done
      if ((i < n)); then
        STRIPPED_COMMAND="${tokens[*]:$i}"
      else
        STRIPPED_COMMAND=""
      fi
      ;;
    *)
      STRIPPED_COMMAND=""
      ;;
  esac
}

# --- Shell payload recursion ---
# When a segment begins with bash/sh/zsh -c <payload> or eval <payload>,
# re-classify the inner payload and propagate the result.
# Bounded by depth to avoid infinite recursion.
# Always returns 0 (safe under set -e).
# Sets CLASSIFY_MATCHED=1 when a verdict was reached; leaves it 0 to abstain.
_SHELL_RECURSE_DEPTH=0
_SHELL_RECURSE_MAX=4

classify_shell_payload() {
  local seg="$1"
  local -a tokens
  read -ra tokens <<<"$seg"
  local n=${#tokens[@]}
  [[ $n -lt 2 ]] && return 0

  local first="${tokens[0]}"
  local payload=""

  case "$first" in
    bash | sh | zsh | dash)
      # bash -c <payload...> [-- args...]
      # flags before -c: -e, -u, -x, -o errexit, etc. are safe to skip
      local i=1
      while ((i < n)); do
        case "${tokens[$i]}" in
          -c)
            ((i++)) || true
            # Everything from here to end-of-segment is the payload.
            # parse_segments already stripped quoting so it's flat tokens here.
            payload="${tokens[*]:$i}"
            break
            ;;
          --)
            # End of flags; next token would be script file, not -c payload
            break
            ;;
          -*)
            # Skip other shell flags (-e, -u, -x, -o OPTION)
            case "${tokens[$i]}" in
              -o) ((i += 2)) || true ;;
              *) ((i++)) || true ;;
            esac
            ;;
          *)
            # Bare argument before -c — e.g. a script filename; not -c form
            break
            ;;
        esac
      done
      ;;
    eval)
      # eval <payload...>
      payload="${tokens[*]:1}"
      ;;
    *)
      return 0
      ;;
  esac

  [[ -z "$payload" ]] && return 0

  # Depth guard — abstain if we'd recurse too deep
  if ((_SHELL_RECURSE_DEPTH >= _SHELL_RECURSE_MAX)); then
    return 0
  fi

  ((_SHELL_RECURSE_DEPTH++)) || true

  # Check the inner payload for unsafe redirections first.
  # The outer AST redirect check cannot see through the single-quoted string,
  # so we must parse the payload independently.
  local saved_segment_mode=$SEGMENT_MODE
  SEGMENT_MODE=1
  CLASSIFY_MATCHED=0
  check_redirections_ast "$payload"
  SEGMENT_MODE=$saved_segment_mode
  if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
    # Redirect found in inner payload — propagate deny and return
    ((_SHELL_RECURSE_DEPTH--)) || true
    return 0
  fi

  # Re-parse the inner payload into segments and classify each one
  local inner_segments
  inner_segments=$(parse_segments "$payload")
  if [[ -z "$inner_segments" ]]; then
    # shfmt couldn't parse it — treat as single command
    inner_segments="$payload"
  fi

  local inner_worst=0 inner_worst_reason="" inner_any_classified=0 inner_any_unclassified=0

  while IFS= read -r inner_seg; do
    [[ -z "$inner_seg" ]] && continue
    inner_seg=$(echo "$inner_seg" | sed 's/^ *//; s/ *$//')
    [[ -z "$inner_seg" ]] && continue

    classify_single_command "$inner_seg"
    if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
      inner_any_classified=1
      if ((CLASSIFY_RESULT > inner_worst)); then
        inner_worst=$CLASSIFY_RESULT
        inner_worst_reason="$CLASSIFY_REASON"
      elif [[ -z "$inner_worst_reason" && -n "$CLASSIFY_REASON" ]]; then
        inner_worst_reason="$CLASSIFY_REASON"
      fi
    else
      ((inner_any_unclassified++)) || true
    fi
  done <<<"$inner_segments"

  ((_SHELL_RECURSE_DEPTH--)) || true

  if [[ "$inner_any_classified" -eq 0 ]]; then
    # No classifier had an opinion — abstain (leave CLASSIFY_MATCHED=0)
    return 0
  fi

  if [[ "$inner_any_unclassified" -gt 0 && "$inner_worst" -le 1 ]]; then
    # Mixed classified+unclassified — abstain for allow/ask; deny still propagates
    if ((inner_worst < 2)); then
      return 0
    fi
  fi

  # Propagate the inner result
  CLASSIFY_RESULT=$inner_worst
  CLASSIFY_REASON="$inner_worst_reason"
  CLASSIFY_MATCHED=1
  return 0
}

# --- Classify a single command segment ---
# Sets CLASSIFY_RESULT (0=allow, 1=ask, 2=deny) and CLASSIFY_REASON.
classify_single_command() {
  local command="$1" # shadows the global for classifier reuse
  CLASSIFY_RESULT=0
  CLASSIFY_REASON=""
  CLASSIFY_MATCHED=0

  # --- Shell payload recursion ---
  # bash/sh/zsh -c '...' and eval '...' must classify the inner payload,
  # not just the wrapper shell.  Do this before the first-token fast-path
  # so that e.g. `bash -c 'git reset --hard'` is correctly denied.
  classify_shell_payload "$command"
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  # --- Prefix-wrapper stripping ---
  # sudo, command, nice, timeout unwrap to the real first token so every
  # classifier sees the actual binary rather than the launcher.
  STRIPPED_COMMAND=""
  strip_prefix_wrappers "$command"
  if [[ -n "$STRIPPED_COMMAND" ]]; then
    classify_single_command "$STRIPPED_COMMAND"
    return 0
  fi

  # Run classifiers — each may call allow/ask/deny which sets CLASSIFY_MATCHED
  check_custom_patterns
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_allow_edit
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

  check_curl
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_npm
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_pip
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_uv
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_cargo
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_jvm_tools
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  # No classifier matched — passthrough to Claude Code's built-in permission system
  return 0
}
