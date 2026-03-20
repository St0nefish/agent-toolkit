#!/usr/bin/env bash
# manage-custom-patterns.sh — Add, remove, and list custom command patterns.
#
# Usage:
#   manage-custom-patterns.sh list [--type commands|allow-edit|web]
#   manage-custom-patterns.sh add --scope global|project [--type commands|allow-edit|web] <pattern>
#   manage-custom-patterns.sh remove --scope global|project [--type commands|allow-edit|web] <pattern>
#   manage-custom-patterns.sh set-mode --scope global|project --type web <mode>
set -euo pipefail

command -v jq &>/dev/null || {
  echo "Error: jq is required but not found in PATH" >&2
  exit 1
}

# Override via env vars for testing:
#   COMMAND_PERMISSIONS_GLOBAL  — default: ~/.claude/command-permissions.json
#   COMMAND_PERMISSIONS_PROJECT — default: .claude/command-permissions.json
#   ALLOW_EDIT_PERMISSIONS_GLOBAL  — default: ~/.claude/allow-edit-permissions.json
#   ALLOW_EDIT_PERMISSIONS_PROJECT — default: .claude/allow-edit-permissions.json
#   WEB_PERMISSIONS_GLOBAL  — default: ~/.claude/web-permissions.json
#   WEB_PERMISSIONS_PROJECT — default: .claude/web-permissions.json

SCOPE=""
ACTION=""
PATTERN=""
TYPE="commands"

usage() {
  cat <<'EOF'
Usage: manage-custom-patterns.sh <action> [options] [pattern]

Actions:
  list                         Show all patterns from both scopes
  add --scope <scope> <pat>    Add a pattern/domain (deduped)
  remove --scope <scope> <pat> Remove a pattern/domain
  set-mode --scope <scope> <m> Set web mode (--type web only)

Options:
  --scope global|project       Target file (required for add/remove/set-mode)
  --type commands|allow-edit|web  Config type (default: commands)
  -h, --help                   Show this help
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    list | add | remove | set-mode)
      ACTION="$1"
      shift
      ;;
    --scope)
      SCOPE="$2"
      shift 2
      ;;
    --type)
      TYPE="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      PATTERN="$1"
      shift
      ;;
  esac
done

resolve_files() {
  case "$TYPE" in
    commands)
      GLOBAL_FILE="${COMMAND_PERMISSIONS_GLOBAL:-${HOME}/.claude/command-permissions.json}"
      PROJECT_FILE="${COMMAND_PERMISSIONS_PROJECT:-.claude/command-permissions.json}"
      ;;
    allow-edit)
      GLOBAL_FILE="${ALLOW_EDIT_PERMISSIONS_GLOBAL:-${HOME}/.claude/allow-edit-permissions.json}"
      PROJECT_FILE="${ALLOW_EDIT_PERMISSIONS_PROJECT:-.claude/allow-edit-permissions.json}"
      ;;
    web)
      GLOBAL_FILE="${WEB_PERMISSIONS_GLOBAL:-${HOME}/.claude/web-permissions.json}"
      PROJECT_FILE="${WEB_PERMISSIONS_PROJECT:-.claude/web-permissions.json}"
      ;;
    *)
      echo "Error: --type must be 'commands', 'allow-edit', or 'web'" >&2
      exit 1
      ;;
  esac
}

resolve_files

resolve_file() {
  case "$SCOPE" in
    global) echo "$GLOBAL_FILE" ;;
    project) echo "$PROJECT_FILE" ;;
    *)
      echo "Error: --scope must be 'global' or 'project'" >&2
      exit 1
      ;;
  esac
}

read_patterns() {
  local file="$1"
  if [[ -f "$file" ]]; then
    jq -r '.allow[]? // empty' "$file" 2>/dev/null
  fi
}

# --- Web-specific helpers ---

read_web_mode() {
  local file="$1"
  if [[ -f "$file" ]]; then
    jq -r '.mode // "off"' "$file" 2>/dev/null || echo "off"
  else
    echo "(not configured)"
  fi
}

read_web_domains() {
  local file="$1"
  if [[ -f "$file" ]]; then
    jq -r '.domains[]? // empty' "$file" 2>/dev/null
  fi
}

do_list_web() {
  echo "  Type: web"
  for scope_name in global project; do
    local file
    if [[ "$scope_name" == "global" ]]; then file="$GLOBAL_FILE"; else file="$PROJECT_FILE"; fi
    local mode
    mode=$(read_web_mode "$file")
    printf "  [%s] mode: %s\n" "$scope_name" "$mode"
    if [[ -f "$file" ]]; then
      while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        printf "  [%s]   domain: %s\n" "$scope_name" "$d"
      done < <(read_web_domains "$file")
    fi
  done
}

do_add_web() {
  [[ -n "$PATTERN" ]] || {
    echo "Error: domain required" >&2
    exit 1
  }
  local file
  file=$(resolve_file)

  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo '{"mode":"domains","domains":[]}' >"$file"
  fi

  if jq -e --arg d "$PATTERN" '.domains // [] | index($d) != null' "$file" >/dev/null 2>&1; then
    echo "Domain already exists: $PATTERN"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg d "$PATTERN" '.domains = ((.domains // []) + [$d])' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Added to $SCOPE: $PATTERN"
}

do_remove_web() {
  [[ -n "$PATTERN" ]] || {
    echo "Error: domain required" >&2
    exit 1
  }
  local file
  file=$(resolve_file)

  if [[ ! -f "$file" ]]; then
    echo "No web config file at $file"
    return 0
  fi

  if ! jq -e --arg d "$PATTERN" '.domains // [] | index($d) != null' "$file" >/dev/null 2>&1; then
    echo "Domain not found: $PATTERN"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg d "$PATTERN" '.domains |= map(select(. != $d))' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Removed from $SCOPE: $PATTERN"
}

do_set_mode() {
  [[ "$TYPE" == "web" ]] || {
    echo "Error: set-mode is only valid with --type web" >&2
    exit 1
  }
  [[ -n "$PATTERN" ]] || {
    echo "Error: mode required (off, all, domains)" >&2
    exit 1
  }
  case "$PATTERN" in
    off | all | domains) ;;
    *)
      echo "Error: mode must be 'off', 'all', or 'domains'" >&2
      exit 1
      ;;
  esac

  local file
  file=$(resolve_file)

  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo '{"mode":"off","domains":[]}' >"$file"
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg m "$PATTERN" '.mode = $m' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Set $SCOPE mode: $PATTERN"
}

# --- Standard (commands/allow-edit) functions ---

do_list() {
  local found=false label
  if [[ "$TYPE" == "allow-edit" ]]; then
    label="allow-edit"
  else
    label="commands"
  fi
  echo "  Type: $label"
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
    if [[ "$TYPE" == "allow-edit" ]]; then
      echo "  (no custom allow-edit commands — using built-in defaults: chmod ln mkdir cp mv touch install tee)"
    else
      echo "  (no custom patterns defined)"
    fi
  fi
}

do_add() {
  [[ -n "$PATTERN" ]] || {
    echo "Error: pattern required" >&2
    exit 1
  }
  local file
  file=$(resolve_file)

  # Create file with empty allow array if absent
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    echo '{"allow":[]}' >"$file"
  fi

  # Check for duplicate
  if jq -e --arg p "$PATTERN" '.allow | index($p) != null' "$file" >/dev/null 2>&1; then
    echo "Pattern already exists: $PATTERN"
    return 0
  fi

  # Append pattern
  local tmp
  tmp=$(mktemp)
  jq --arg p "$PATTERN" '.allow += [$p]' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Added to $SCOPE: $PATTERN"
}

do_remove() {
  [[ -n "$PATTERN" ]] || {
    echo "Error: pattern required" >&2
    exit 1
  }
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
  jq --arg p "$PATTERN" '.allow |= map(select(. != $p))' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "Removed from $SCOPE: $PATTERN"
}

# --- Dispatch ---
if [[ "$TYPE" == "web" ]]; then
  case "$ACTION" in
    list) do_list_web ;;
    add) do_add_web ;;
    remove) do_remove_web ;;
    set-mode) do_set_mode ;;
    *)
      echo "Error: action required (list, add, remove, set-mode)" >&2
      usage
      ;;
  esac
else
  case "$ACTION" in
    list) do_list ;;
    add) do_add ;;
    remove) do_remove ;;
    set-mode)
      echo "Error: set-mode is only valid with --type web" >&2
      exit 1
      ;;
    *)
      echo "Error: action required (list, add, remove)" >&2
      usage
      ;;
  esac
fi
