# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Habit gates ---
# Hard-deny patterns that are technically safe but that the user's own rules
# forbid. The deny reason is shown to Claude, so each message names the
# alternative to use instead.
#
# Operate on the FULL original command (like check_redirections_ast) and are
# called from cmd-gate.sh main() before segmentation. Set SEGMENT_MODE=1 before
# calling; a match sets CLASSIFY_MATCHED=1 / CLASSIFY_RESULT=2 via deny().

# Leading `cd <dir> && ...` / `cd <dir>; ...`.
# Denied only when the cd is provably avoidable:
#   - <dir> is the current working directory (redundant), or
#   - the chained command is git (use relative paths, or `git -C <dir>` for a
#     different repo).
# Other uses (cd into a subdir for a build tool with no -C/--prefix flag, cd to
# another path, dynamic targets) pass through unchanged.
check_cd_prefix() {
  local cmd="$1"
  local re='^[[:space:]]*cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*(&&|;)[[:space:]]*([^[:space:];&|]+)'
  [[ "$cmd" =~ $re ]] || return 0
  local target="${BASH_REMATCH[1]}" next="${BASH_REMATCH[3]}"

  # Strip one layer of matching quotes; abstain on anything dynamic.
  target="${target#[\"\']}"
  target="${target%[\"\']}"
  case "$target" in
    *[\$\`~*?\\]* | -* | "") return 0 ;;
  esac

  local abs
  case "$target" in
    /*) abs="$target" ;;
    *) abs="$PWD/$target" ;;
  esac
  abs=$(realpath -m -- "$abs" 2>/dev/null) || return 0
  local here
  here=$(realpath -m -- "$PWD" 2>/dev/null) || return 0

  if [[ "$abs" == "$here" ]]; then
    deny "Redundant 'cd $target': it is already the working directory. Drop 'cd <dir> &&' and run the command directly with relative paths."
    return 0
  fi
  if [[ "$next" == "git" ]]; then
    deny "Don't prefix git with 'cd <dir> &&'. Run git from the working directory with relative paths (e.g. git add path/to/file), or use 'git -C <dir> ...' only when targeting a different repo."
    return 0
  fi
}

# python/python3 used to parse or emit JSON (-c, heredoc, or -m json.tool).
# The user's rule is to always use jq. Set PERMISSION_MANAGER_ALLOW_PYTHON_JSON=1
# to disable (the classifier test suite does, since it uses `import json` as a
# neutral payload).
check_python_json() {
  [[ "${PERMISSION_MANAGER_ALLOW_PYTHON_JSON:-0}" == "1" ]] && return 0
  local cmd="$1"
  local py_re='(^|[[:space:];&|(`])python3?[[:space:]]'
  local json_re='(import[[:space:]]+json|from[[:space:]]+json[[:space:]]+import|json\.(load|loads|dump|dumps)[[:space:]]*\(|-m[[:space:]]+json\.tool)'
  if [[ "$cmd" =~ $py_re && "$cmd" =~ $json_re ]]; then
    deny "Don't use python for JSON. Use jq instead (e.g. jq '.key' file.json, jq -r '.items[].name', jq -s for slurp, jq . to pretty-print)."
  fi
}
