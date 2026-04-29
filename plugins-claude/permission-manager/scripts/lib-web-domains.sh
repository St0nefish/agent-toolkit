# shellcheck shell=bash
# lib-web-domains.sh — Shared web-permissions config loader and domain matcher.
# Sourced by web-gate.sh (WebFetch/WebSearch gating) and classifiers/curl.sh
# (Bash curl gating) so both consult the same allow-list.
#
# Config file shape (global: ~/.claude/web-permissions.json,
#                    project: .claude/web-permissions.json):
#   { "mode": "off|all|domains", "domains": ["github.com", ...] }
#
# Mode resolution: project mode wins over global; domains arrays merge (union).
#
# Override paths via env vars for testing:
#   WEB_PERMISSIONS_GLOBAL  — default: ~/.claude/web-permissions.json
#   WEB_PERMISSIONS_PROJECT — default: .claude/web-permissions.json
#
# After web_load_config:
#   WEB_MODE     — "off" | "all" | "domains"
#   WEB_DOMAINS  — array of allow-listed domains (deduplicated)

WEB_MODE="off"
WEB_DOMAINS=()
WEB_CONFIG_LOADED=0

web_load_config() {
  [[ "$WEB_CONFIG_LOADED" -eq 1 ]] && return 0
  WEB_CONFIG_LOADED=1

  local global_file="${WEB_PERMISSIONS_GLOBAL:-${HOME}/.claude/web-permissions.json}"
  local project_file="${WEB_PERMISSIONS_PROJECT:-.claude/web-permissions.json}"

  local global_mode="off" project_mode="off"
  if [[ -f "$global_file" ]]; then
    global_mode=$(jq -r '.mode // "off"' "$global_file" 2>/dev/null || echo "off")
  fi
  if [[ -f "$project_file" ]]; then
    project_mode=$(jq -r '.mode // "off"' "$project_file" 2>/dev/null || echo "off")
    WEB_MODE="$project_mode"
  else
    WEB_MODE="$global_mode"
  fi

  WEB_DOMAINS=()
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    WEB_DOMAINS+=("$d")
  done < <({
    [[ -f "$global_file" ]] && jq -r '.domains[]? // empty' "$global_file" 2>/dev/null
    [[ -f "$project_file" ]] && jq -r '.domains[]? // empty' "$project_file" 2>/dev/null
  } | sort -u)
}

web_extract_domain() {
  local url="$1"
  local host="${url#*://}"
  host="${host%%/*}"
  host="${host%%\?*}"
  host="${host%%#*}"
  host="${host%%:*}"
  host="${host##*@}"
  printf '%s' "$host"
}

web_domain_matches() {
  local check="$1" allowed
  for allowed in "${WEB_DOMAINS[@]+"${WEB_DOMAINS[@]}"}"; do
    [[ "$check" == "$allowed" ]] && return 0
    [[ "$check" == *".${allowed}" ]] && return 0
  done
  return 1
}
