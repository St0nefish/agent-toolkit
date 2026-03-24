# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Allow-edit classifier ---
# Promotes safe project-local write commands (chmod, ln, mkdir, etc.) to "allow"
# when the user is in allow-edits mode. Only fires when ALLOW_EDIT_ACTIVE=1.
#
# Project-scoping: all non-flag arguments must resolve within $PWD.
# If any path is outside the project, the classifier returns without matching
# (falls through to normal permission handling).

is_within_project() {
  local path="$1"
  local resolved

  # Absolute paths: check prefix directly
  if [[ "$path" == /* ]]; then
    if [[ -e "$path" ]]; then
      resolved=$(realpath "$path" 2>/dev/null) || return 1
    else
      # Walk up to find existing ancestor
      local check="$path"
      while [[ "$check" != "/" && "$check" != "." ]]; do
        if [[ -e "$check" ]]; then
          resolved=$(realpath "$check" 2>/dev/null)/$(realpath --relative-to="$check" "$path" 2>/dev/null || echo "${path#"$check"/}") || return 1
          break
        fi
        check=$(dirname "$check")
      done
      [[ -n "${resolved:-}" ]] || return 1
    fi
    [[ "$resolved" == "$PWD"/* || "$resolved" == "$PWD" ]]
    return
  fi

  # Relative paths: resolve against $PWD
  if [[ -e "$path" ]]; then
    resolved=$(cd "$PWD" && realpath "$path" 2>/dev/null) || return 1
  else
    # For relative paths to non-existent files, resolve what we can
    local dir
    dir=$(dirname "$path")
    if [[ -d "$dir" ]]; then
      resolved=$(cd "$PWD" && realpath "$dir" 2>/dev/null)/$(basename "$path") || return 1
    else
      # Parent doesn't exist either — it's relative to $PWD, so it stays within project
      # unless it contains ".." that escapes
      resolved="$PWD/$path"
    fi
  fi
  # Normalize ".." components for security
  if [[ "$resolved" == *".."* ]]; then
    # Can't safely resolve — treat as outside
    return 1
  fi
  [[ "$resolved" == "$PWD"/* || "$resolved" == "$PWD" ]]
}

check_allow_edit() {
  # Only active in allow-edits mode
  [[ "${ALLOW_EDIT_ACTIVE:-0}" -eq 1 ]] || return 0

  local -a tokens
  read -ra tokens <<<"$command"
  local tool="${tokens[0]:-}"

  # Check if tool is in the allow-edit commands list
  local found=false
  for cmd in "${ALLOW_EDIT_COMMANDS[@]+"${ALLOW_EDIT_COMMANDS[@]}"}"; do
    if [[ "$tool" == "$cmd" ]]; then
      found=true
      break
    fi
  done
  [[ "$found" == true ]] || return 0

  # Project-scoping: check all non-flag arguments resolve within $PWD
  local i
  for ((i = 1; i < ${#tokens[@]}; i++)); do
    local arg="${tokens[$i]}"
    # Skip flags
    [[ "$arg" == -* ]] && continue
    # Check path is within project
    if ! is_within_project "$arg"; then
      return 0 # outside project → don't match, fall through
    fi
  done

  allow "$tool is a safe project-local write"
}
