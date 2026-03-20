#!/usr/bin/env bash
# state-manager.sh — Read/write incremental analysis state
#
# State file: ~/.claude/session-analysis/state.json
# Subcommands: read, is-analyzed <id>, mark-analyzed <id> <slug> <ts>, clear [--project <slug>], summary

set -euo pipefail

STATE_DIR="${CLAUDE_STATE_DIR:-$HOME/.claude/session-analysis}"
STATE_FILE="$STATE_DIR/state.json"

ensure_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}'
  else
    cat "$STATE_FILE"
  fi
}

write_state() {
  mkdir -p "$STATE_DIR"
  local tmp
  tmp=$(mktemp "$STATE_DIR/state.XXXXXX")
  cat >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  read)
    ensure_state
    ;;

  is-analyzed)
    local_id="${1:?Usage: state-manager.sh is-analyzed <session-id>}"
    state=$(ensure_state)
    if echo "$state" | jq -e --arg id "$local_id" '.analyzed[$id]' &>/dev/null; then
      exit 0
    else
      exit 1
    fi
    ;;

  mark-analyzed)
    local_id="${1:?Usage: state-manager.sh mark-analyzed <id> <slug> <ts>}"
    slug="${2:?}"
    ts="${3:?}"
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    state=$(ensure_state)
    echo "$state" | jq --arg id "$local_id" \
      --arg slug "$slug" \
      --arg ts "$ts" \
      --arg now "$now" \
      '.version = 1 | .last_run = $now | .analyzed[$id] = {project_slug: $slug, analyzed_at: $now, session_started: $ts}' |
      write_state
    ;;

  clear)
    project_filter=""
    if [[ "${1:-}" == "--project" ]]; then
      project_filter="${2:?Usage: state-manager.sh clear --project <slug>}"
    fi
    state=$(ensure_state)
    if [[ -n "$project_filter" ]]; then
      echo "$state" | jq --arg slug "$project_filter" \
        '.analyzed = (.analyzed // {} | with_entries(select(.value.project_slug != $slug)))' |
        write_state
    else
      echo '{}' | write_state
    fi
    ;;

  summary)
    state=$(ensure_state)
    echo "$state" | jq '{
      version: (.version // 0),
      last_run: (.last_run // null),
      total_analyzed: ((.analyzed // {}) | length),
      by_project: ((.analyzed // {}) | [.[].project_slug] | group_by(.) | map({(.[0]): length}) | add // {})
    }'
    ;;

  *)
    echo "Usage: state-manager.sh {read|is-analyzed|mark-analyzed|clear|summary}" >&2
    exit 2
    ;;
esac
