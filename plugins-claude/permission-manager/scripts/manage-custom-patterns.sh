#!/usr/bin/env bash
# manage-custom-patterns.sh — Add, remove, and list custom command patterns.
#
# Usage:
#   manage-custom-patterns.sh list
#   manage-custom-patterns.sh add --scope global|project <pattern>
#   manage-custom-patterns.sh remove --scope global|project <pattern>
set -euo pipefail

command -v jq &>/dev/null || { echo "Error: jq is required but not found in PATH" >&2; exit 1; }

# Override via env vars for testing:
#   COMMAND_PERMISSIONS_GLOBAL  — default: ~/.claude/command-permissions.json
#   COMMAND_PERMISSIONS_PROJECT — default: .claude/command-permissions.json
GLOBAL_FILE="${COMMAND_PERMISSIONS_GLOBAL:-${HOME}/.claude/command-permissions.json}"
PROJECT_FILE="${COMMAND_PERMISSIONS_PROJECT:-.claude/command-permissions.json}"

SCOPE=""
ACTION=""
PATTERN=""

usage() {
  cat <<'EOF'
Usage: manage-custom-patterns.sh <action> [options] [pattern]

Actions:
  list                         Show all patterns from both scopes
  add --scope <scope> <pat>    Add a pattern (deduped)
  remove --scope <scope> <pat> Remove a pattern

Options:
  --scope global|project       Target file (required for add/remove)
  -h, --help                   Show this help
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    list|add|remove) ACTION="$1"; shift ;;
    --scope) SCOPE="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    *) PATTERN="$1"; shift ;;
  esac
done

resolve_file() {
  case "$SCOPE" in
    global)  echo "$GLOBAL_FILE" ;;
    project) echo "$PROJECT_FILE" ;;
    *) echo "Error: --scope must be 'global' or 'project'" >&2; exit 1 ;;
  esac
}

read_patterns() {
  local file="$1"
  if [[ -f "$file" ]]; then
    jq -r '.allow[]? // empty' "$file" 2>/dev/null
  fi
}

do_list() {
  local found=false
  for scope_name in global project; do
    local file
    if [[ "$scope_name" == "global" ]]; then file="$GLOBAL_FILE"; else file="$PROJECT_FILE"; fi
    if [[ -f "$file" ]]; then
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        printf "  [%s] %s\n" "$scope_name" "$p"
        found=true
      done < <(read_patterns "$file")
    fi
  done
  if [[ "$found" == false ]]; then
    echo "  (no custom patterns defined)"
  fi
}

do_add() {
  [[ -n "$PATTERN" ]] || { echo "Error: pattern required" >&2; exit 1; }
  local file
  file=$(resolve_file)

  # Create file with empty allow array if absent
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo '{"allow":[]}' > "$file"
  fi

  # Check for duplicate
  if jq -e --arg p "$PATTERN" '.allow | index($p) != null' "$file" >/dev/null 2>&1; then
    echo "Pattern already exists: $PATTERN"
    return 0
  fi

  # Append pattern
  local tmp
  tmp=$(mktemp)
  jq --arg p "$PATTERN" '.allow += [$p]' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "Added to $SCOPE: $PATTERN"
}

do_remove() {
  [[ -n "$PATTERN" ]] || { echo "Error: pattern required" >&2; exit 1; }
  local file
  file=$(resolve_file)

  if [[ ! -f "$file" ]]; then
    echo "No patterns file at $file"
    return 0
  fi

  # Check if pattern exists
  if ! jq -e --arg p "$PATTERN" '.allow | index($p) != null' "$file" >/dev/null 2>&1; then
    echo "Pattern not found: $PATTERN"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg p "$PATTERN" '.allow |= map(select(. != $p))' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "Removed from $SCOPE: $PATTERN"
}

case "$ACTION" in
  list)   do_list ;;
  add)    do_add ;;
  remove) do_remove ;;
  *)      echo "Error: action required (list, add, remove)" >&2; usage ;;
esac
