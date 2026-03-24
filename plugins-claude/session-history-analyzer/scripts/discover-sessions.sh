#!/usr/bin/env bash
# discover-sessions.sh — Enumerate Claude Code sessions under ~/.claude/projects/
#
# Args: [--since <ISO8601>] [--project <slug>]
# Output: newline-delimited JSON, one record per session
#   {session_id, project_slug, project_path, jsonl_path, mtime_epoch, size_bytes}

set -euo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
SINCE=""
PROJECT_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE="$2"
      shift 2
      ;;
    --project)
      PROJECT_FILTER="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Convert --since to epoch for comparison
SINCE_EPOCH=0
if [[ -n "$SINCE" ]]; then
  if date -j -f "%Y-%m-%dT%H:%M:%S" "${SINCE%%.*}" "+%s" &>/dev/null; then
    # macOS
    SINCE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${SINCE%%.*}" "+%s" 2>/dev/null || date -j -f "%Y-%m-%d" "$SINCE" "+%s" 2>/dev/null || echo 0)
  else
    # GNU date
    SINCE_EPOCH=$(date -d "$SINCE" "+%s" 2>/dev/null || echo 0)
  fi
fi

if [[ ! -d "$PROJECTS_DIR" ]]; then
  exit 0
fi

# Decode project slug to filesystem path via heuristic
decode_slug() {
  local slug="$1"
  # Slugs are paths with / replaced by - and leading - for /
  local path
  path=$(echo "$slug" | sed 's/-/\//g')
  # Try the decoded path first
  if [[ -d "$path" ]]; then
    echo "$path"
    return
  fi
  # Try common prefix patterns (the slug encodes absolute paths)
  echo "$path"
}

for project_dir in "$PROJECTS_DIR"/*/; do
  [[ -d "$project_dir" ]] || continue

  slug=$(basename "$project_dir")

  # Apply --project filter
  if [[ -n "$PROJECT_FILTER" && "$slug" != *"$PROJECT_FILTER"* ]]; then
    continue
  fi

  project_path=$(decode_slug "$slug")

  # Find JSONL files, excluding subagents/ subdirectory
  while IFS= read -r jsonl_path; do
    [[ -f "$jsonl_path" ]] || continue

    # Skip files inside subagents/ subdirectory
    local_path="${jsonl_path#"$project_dir"}"
    if [[ "$local_path" == subagents/* ]]; then
      continue
    fi

    # Get file metadata
    if stat -f '%m %z' "$jsonl_path" &>/dev/null; then
      # macOS stat
      read -r mtime_epoch size_bytes < <(stat -f '%m %z' "$jsonl_path")
    else
      # GNU stat
      read -r mtime_epoch size_bytes < <(stat -c '%Y %s' "$jsonl_path")
    fi

    # Apply --since filter
    if [[ "$SINCE_EPOCH" -gt 0 && "$mtime_epoch" -lt "$SINCE_EPOCH" ]]; then
      continue
    fi

    session_id=$(basename "$jsonl_path" .jsonl)

    jq -n --arg sid "$session_id" \
      --arg slug "$slug" \
      --arg ppath "$project_path" \
      --arg jpath "$jsonl_path" \
      --argjson mtime "$mtime_epoch" \
      --argjson size "$size_bytes" \
      '{session_id: $sid, project_slug: $slug, project_path: $ppath, jsonl_path: $jpath, mtime_epoch: $mtime, size_bytes: $size}'

  done < <(find "$project_dir" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null)
done
