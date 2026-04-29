# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Inline Python classifier ---
# Handles `python[3] -c "<code>"` and `python[3] -m <safe-module>` invocations
# by statically analysing the inline source via check-python-readonly.py.
#
# Operates on the FULL original command (not per-segment), since the shfmt
# segmenter strips quoted -c arguments. Called from cmd-gate.sh main() before
# segmentation, similar to check_redirections_ast.
#
# Scope: single-statement invocations only. Compound/piped/substituted forms
# abstain (no opinion -> falls through to normal segmentation).

# -m modules that only inspect input or print built-in info -- no writes.
# Excludes anything network-capable (http.server, smtpd) or that runs arbitrary
# code (timeit, profile, pdb). json.tool is excluded because its 2-arg form
# `python -m json.tool <infile> <outfile>` writes to <outfile>.
PYTHON_SAFE_M_MODULES="tabnanny base64 dis tokenize this calendar uuid"

check_python_inline() {
  local cmd="$1"
  local ast
  ast=$(printf '%s' "$cmd" | shfmt --tojson 2>/dev/null) || return 0
  [[ -n "$ast" ]] || return 0

  # Must be exactly one top-level statement.
  local stmt_count
  stmt_count=$(echo "$ast" | jq '.Stmts // [] | length')
  [[ "$stmt_count" == "1" ]] || return 0

  # Must be a CallExpr (a simple command, not a pipe/subshell/binary).
  local cmd_type
  cmd_type=$(echo "$ast" | jq -r '.Stmts[0].Cmd.Type // empty')
  [[ "$cmd_type" == "CallExpr" ]] || return 0

  # Abstain if there are inline env-var assignments (`PYTHONPATH=/tmp python3 -c
  # "import json"` would import a malicious /tmp/json.py without our payload
  # check seeing anything dangerous). Also covers PYTHONSTARTUP, LD_PRELOAD,
  # and any other prefix variable.
  local assign_count
  assign_count=$(echo "$ast" | jq '.Stmts[0].Cmd.Assigns // [] | length')
  [[ "$assign_count" == "0" ]] || return 0

  # First arg must be python or python3 as a pure literal.
  local prog
  prog=$(echo "$ast" | jq -r '
    .Stmts[0].Cmd.Args[0] |
    if ([.. | objects | select(.Type?) | .Type] | all(. == "Lit")) then
      [.. | objects | select(.Type? == "Lit") | .Value] | join("")
    else "" end
  ')
  case "$prog" in
    python | python3) ;;
    *) return 0 ;;
  esac

  # Walk remaining args looking for -c <code> or -m <module>.
  # Skip flags that take no value, and flag-with-value pairs.
  local args_json n i=1
  args_json=$(echo "$ast" | jq -c '.Stmts[0].Cmd.Args')
  n=$(echo "$args_json" | jq 'length')

  local mode="" payload=""
  while ((i < n)); do
    local arg_lit
    arg_lit=$(echo "$args_json" | jq -r --argjson i "$i" '
      .[$i] |
      if ([.. | objects | select(.Type?) | .Type] | all(. == "Lit")) then
        [.. | objects | select(.Type? == "Lit") | .Value] | join("")
      else "" end
    ')
    case "$arg_lit" in
      --version | -V)
        allow "$prog --version is read-only"
        return 0
        ;;
      -c)
        mode="c"
        i=$((i + 1))
        if ((i < n)); then
          # Abstain if -c arg has dynamic parts (CmdSubst, ParamExp, etc.) or
          # ANSI-C quoting ($'...'). Bash decodes \x/\n/\u escapes inside
          # $'...' at runtime, so the static source we read differs from what
          # Python actually runs.
          local bad_count
          bad_count=$(echo "$args_json" | jq --argjson i "$i" '
            .[$i] |
            (
              [.. | objects | select(.Type?) | .Type
                | select(. != "Lit" and . != "DblQuoted" and . != "SglQuoted")]
              + [.. | objects | select(.Type? == "SglQuoted" and .Dollar == true)]
            ) | length
          ')
          if [[ "$bad_count" != "0" ]]; then
            return 0
          fi
          payload=$(echo "$args_json" | jq -r --argjson i "$i" '
            .[$i] |
            [.. | objects | (
              if .Type? == "Lit" then .Value
              elif .Type? == "SglQuoted" then .Value
              else empty end
            )] | join("")
          ')
        fi
        break
        ;;
      -m)
        mode="m"
        i=$((i + 1))
        if ((i < n)); then
          payload=$(echo "$args_json" | jq -r --argjson i "$i" '
            .[$i] |
            if ([.. | objects | select(.Type?) | .Type] | all(. == "Lit")) then
              [.. | objects | select(.Type? == "Lit") | .Value] | join("")
            else "" end
          ')
        fi
        break
        ;;
      -u | -S | -E | -I | -O | -OO | -B | -q | -d | -v | -b | -bb | -s | -P | -R)
        i=$((i + 1))
        ;;
      -W | -X | --check-hash-based-pycs)
        i=$((i + 2))
        ;;
      *)
        # First non-flag non-known arg -> script file or unknown; abstain.
        return 0
        ;;
    esac
  done

  if [[ "$mode" == "c" ]]; then
    [[ -n "$payload" ]] || return 0
    local helper="${SCRIPTS_DIR}/check-python-readonly.py"
    [[ -f "$helper" ]] || return 0
    local check_out check_rc=0
    check_out=$(printf '%s' "$payload" | python3 "$helper" 2>&1) || check_rc=$?
    case "$check_rc" in
      0) allow "$prog -c is statically read-only (no writes/network/exec)" ;;
      1) ask "$prog -c not auto-allowed: $check_out" ;;
      *) return 0 ;;
    esac
    return 0
  fi

  if [[ "$mode" == "m" ]]; then
    [[ -n "$payload" ]] || return 0
    for m in $PYTHON_SAFE_M_MODULES; do
      if [[ "$payload" == "$m" ]]; then
        allow "$prog -m $payload is read-only"
        return 0
      fi
    done
    return 0
  fi
}
