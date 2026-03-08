#!/usr/bin/env bash
# merge-permissions.sh — Merge permission groups into settings.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GROUPS_DIR="${SCRIPT_DIR}/../groups"
SETTINGS_FILE="${HOME}/.claude/settings.json"
DRY_RUN=false
MODE="merge"

usage() {
  cat <<'EOF'
Usage: merge-permissions.sh [options] <group1> [group2 ...]

Merge permission groups into Claude Code settings.json.

Options:
  --groups-dir DIR     Directory containing group JSON files (default: ../groups/ relative to script)
  --settings FILE      Target settings file (default: ~/.claude/settings.json)
  --dry-run            Print what would change without writing
  --list               List available groups and exit
  --status             Show which groups are currently applied and exit
  -h, --help           Show this help

Groups are JSON files in the groups directory. Each contains a
"permissions" object with "allow" and/or "deny" arrays.
EOF
  exit 0
}

die() { echo "Error: $*" >&2; exit 1; }

# Ensure jq is available
command -v jq &>/dev/null || die "jq is required but not found in PATH"

# Parse arguments
SELECTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --groups-dir) GROUPS_DIR="$2"; shift 2 ;;
    --settings)   SETTINGS_FILE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --list)       MODE="list"; shift ;;
    --status)     MODE="status"; shift ;;
    -h|--help)    usage ;;
    -*)           die "Unknown option: $1" ;;
    *)            SELECTED+=("$1"); shift ;;
  esac
done

# Resolve groups dir
GROUPS_DIR="$(cd "$GROUPS_DIR" 2>/dev/null && pwd)" || die "Groups directory not found: $GROUPS_DIR"

# List available groups
list_groups() {
  local name count_allow count_deny
  for f in "$GROUPS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .json)"
    count_allow="$(jq -r '.permissions.allow // [] | length' "$f")"
    count_deny="$(jq -r '.permissions.deny // [] | length' "$f")"
    if [[ "$count_deny" -gt 0 ]]; then
      printf "  %-16s %3d allow, %d deny\n" "$name" "$count_allow" "$count_deny"
    else
      printf "  %-16s %3d allow\n" "$name" "$count_allow"
    fi
  done
}

# Read settings file, creating a skeleton if missing
read_settings() {
  if [[ -f "$SETTINGS_FILE" ]]; then
    cat "$SETTINGS_FILE"
  else
    echo '{"permissions":{"allow":[],"deny":[]}}'
  fi
}

# Show application status for each group
show_status() {
  local settings
  settings="$(read_settings)"

  for f in "$GROUPS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local name total applied
    name="$(basename "$f" .json)"

    # Count total entries (allow + deny)
    total="$(jq -r '[(.permissions.allow // []), (.permissions.deny // [])] | add | length' "$f")"

    # Count how many of those entries exist in settings
    applied="$(jq -r --argjson settings "$settings" '
      [
        (.permissions.allow // [])[] as $e |
          if ($settings.permissions.allow // [] | index($e)) then 1 else empty end
      ] + [
        (.permissions.deny // [])[] as $e |
          if ($settings.permissions.deny // [] | index($e)) then 1 else empty end
      ] | length
    ' "$f")"

    local label
    if [[ "$applied" -eq "$total" ]]; then
      label="applied"
    elif [[ "$applied" -gt 0 ]]; then
      label="partial ${applied}/${total}"
    else
      label="missing"
    fi
    printf "  %-16s [%s]\n" "$name" "$label"
  done
}

# Merge selected groups into settings
do_merge() {
  [[ ${#SELECTED[@]} -gt 0 ]] || die "No groups specified. Use --list to see available groups."

  local settings
  settings="$(read_settings)"

  local total_new_allow=0 total_new_deny=0

  for group in "${SELECTED[@]}"; do
    local group_file="${GROUPS_DIR}/${group}.json"
    [[ -f "$group_file" ]] || die "Group file not found: ${group}.json"

    # Compute new entries for this group
    local new_allow new_deny
    new_allow="$(jq -r --argjson settings "$settings" '
      [(.permissions.allow // [])[] as $e |
        if ($settings.permissions.allow // [] | index($e)) then empty else $e end]
    ' "$group_file")"

    new_deny="$(jq -r --argjson settings "$settings" '
      [(.permissions.deny // [])[] as $e |
        if ($settings.permissions.deny // [] | index($e)) then empty else $e end]
    ' "$group_file")"

    local count_a count_d
    count_a="$(echo "$new_allow" | jq 'length')"
    count_d="$(echo "$new_deny" | jq 'length')"

    if [[ "$count_a" -gt 0 || "$count_d" -gt 0 ]]; then
      printf "  %-16s +%d allow, +%d deny\n" "$group" "$count_a" "$count_d"
      if [[ "$count_a" -gt 0 ]]; then
        echo "$new_allow" | jq -r '.[]' | sed 's/^/                     allow  /'
      fi
      if [[ "$count_d" -gt 0 ]]; then
        echo "$new_deny" | jq -r '.[]' | sed 's/^/                     deny   /'
      fi
    else
      printf "  %-16s (already applied)\n" "$group"
    fi

    # Accumulate into settings
    settings="$(echo "$settings" | jq --argjson a "$new_allow" --argjson d "$new_deny" '
      .permissions.allow = ((.permissions.allow // []) + $a | unique | sort) |
      .permissions.deny  = ((.permissions.deny  // []) + $d | unique | sort)
    ')"

    total_new_allow=$((total_new_allow + count_a))
    total_new_deny=$((total_new_deny + count_d))
  done

  echo ""
  if [[ "$total_new_allow" -eq 0 && "$total_new_deny" -eq 0 ]]; then
    echo "Nothing to add — all entries already present."
    return 0
  fi

  echo "Total: +${total_new_allow} allow, +${total_new_deny} deny"

  if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "(dry run — no changes written)"
    return 0
  fi

  # Write back
  local tmp
  tmp="$(mktemp)"
  echo "$settings" | jq '.' > "$tmp"

  # Create parent directory if needed
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  mv "$tmp" "$SETTINGS_FILE"
  echo "Written to: ${SETTINGS_FILE}"
}

# Dispatch
case "$MODE" in
  list)
    echo "Available permission groups:"
    list_groups
    ;;
  status)
    echo "Permission group status (against ${SETTINGS_FILE}):"
    show_status
    ;;
  merge)
    do_merge
    ;;
esac
