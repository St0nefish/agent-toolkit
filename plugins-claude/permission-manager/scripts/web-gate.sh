#!/usr/bin/env bash
# web-gate.sh — PreToolUse hook for WebFetch/WebSearch gating.
# Single authority for web permissions across Claude Code and Copilot CLI.
#
# Config: web-permissions.json (global: ~/.claude/, project: .claude/)
#   { "mode": "off|all|domains", "domains": ["github.com", ...] }
#
# Mode behavior:
#   off     — passthrough (exit 0); settings.json entries remain authoritative
#   all     — allow all GET requests; ask on POST/PUT/DELETE/PATCH
#   domains — allow-list check; ask on unmatched domains or mutating methods
#
# WebSearch is always allowed when mode is "all" or "domains" (read-only).
# Scope resolution: project mode wins over global; domains arrays merge.

set -euo pipefail

HOOK_INPUT=$(cat)
# shellcheck source=scripts/hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

# Guard: only handle WebFetch and WebSearch
[[ "$HOOK_TOOL_NAME" == "WebFetch" || "$HOOK_TOOL_NAME" == "WebSearch" ]] || exit 0

# --- Bypass permissions mode ---
if [[ "$HOOK_PERMISSION_MODE" == "bypassPermissions" ]]; then
  exit 0
fi

# --- Config loading ---
# shellcheck source=lib-web-domains.sh
source "$(dirname "$0")/lib-web-domains.sh"
web_load_config
MODE="$WEB_MODE"

# off → passthrough
if [[ "$MODE" == "off" ]]; then
  exit 0
fi

# --- Extract request details ---
if [[ "$HOOK_FORMAT" == "copilot" ]]; then
  URL=$(echo "$HOOK_INPUT" | jq -r 'try (.toolArgs | fromjson | .url) catch ""' 2>/dev/null || echo "")
  METHOD=$(echo "$HOOK_INPUT" | jq -r 'try (.toolArgs | fromjson | .method) catch "GET"' 2>/dev/null || echo "GET")
else
  URL=$(echo "$HOOK_INPUT" | jq -r '.tool_input.url // ""')
  METHOD=$(echo "$HOOK_INPUT" | jq -r '.tool_input.method // "GET"')
fi

# Normalize method to uppercase
METHOD=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')
# Default to GET if empty
[[ -z "$METHOD" ]] && METHOD="GET"

# --- Audit logging ---
log_decision() {
  local decision="$1" reason="$2"
  local log_file="${PERMISSION_AUDIT_LOG:-${HOME}/.claude/permission-audit.jsonl}"
  mkdir -p "$(dirname "$log_file")"
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg tool "$HOOK_TOOL_NAME" \
    --arg url "$URL" \
    --arg method "$METHOD" \
    --arg decision "$decision" \
    --arg reason "$reason" \
    --arg mode "$MODE" \
    --arg project "$(basename "$PWD")" \
    --arg cwd "$PWD" \
    '{ts:$ts,tool:$tool,url:$url,method:$method,decision:$decision,reason:$reason,mode:$mode,project:$project,cwd:$cwd}' \
    >>"$log_file"
}

# --- WebSearch: always allow in all/domains modes ---
if [[ "$HOOK_TOOL_NAME" == "WebSearch" ]]; then
  log_decision "allow" "web-gate: WebSearch allowed (mode=$MODE)"
  hook_allow "web-gate: WebSearch allowed (mode=$MODE)"
  exit 0
fi

# --- WebFetch: mutating methods always ask ---
if [[ "$METHOD" != "GET" && "$METHOD" != "HEAD" ]]; then
  log_decision "ask" "web-gate: mutating method $METHOD requires approval"
  hook_ask "web-gate: mutating method $METHOD requires approval"
  exit 0
fi

# --- WebFetch GET: mode-based decision ---
if [[ "$MODE" == "all" ]]; then
  log_decision "allow" "web-gate: all web access allowed (mode=all)"
  hook_allow "web-gate: all web access allowed (mode=all)"
  exit 0
fi

# Mode is "domains" — extract domain from URL and check allow-list
DOMAIN=$(web_extract_domain "$URL")

if [[ ${#WEB_DOMAINS[@]} -gt 0 ]] && web_domain_matches "$DOMAIN"; then
  log_decision "allow" "web-gate: domain $DOMAIN in allow-list"
  hook_allow "web-gate: domain $DOMAIN in allow-list"
  exit 0
fi

# Domain not in allow-list — ask
log_decision "ask" "web-gate: domain $DOMAIN not in allow-list"
hook_ask "web-gate: domain $DOMAIN not in allow-list"
exit 0
