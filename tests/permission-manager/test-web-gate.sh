#!/usr/bin/env bash
# test-web-gate.sh — Test harness for web-gate.sh WebFetch/WebSearch gating.
#
# Usage: bash tests/permission-manager/test-web-gate.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/web-gate.sh"
MANAGE_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/manage-custom-patterns.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# Temp directory for config files and audit log
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

export WEB_PERMISSIONS_GLOBAL="$TEMP_DIR/global-web-permissions.json"
export WEB_PERMISSIONS_PROJECT="$TEMP_DIR/project-web-permissions.json"
export PERMISSION_AUDIT_LOG="$TEMP_DIR/audit.jsonl"

# --- Helpers ---

reset_config() {
  rm -f "$WEB_PERMISSIONS_GLOBAL" "$WEB_PERMISSIONS_PROJECT" "$PERMISSION_AUDIT_LOG"
}

write_global() {
  echo "$1" >"$WEB_PERMISSIONS_GLOBAL"
}

write_project() {
  echo "$1" >"$WEB_PERMISSIONS_PROJECT"
}

run_test() {
  local expected="$1" tool="$2" url="$3" label="${4:-$tool $url}" format="${5:-claude}" method="${6:-GET}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local payload raw result
  if [[ "$format" == "copilot" ]]; then
    local args_json
    args_json=$(jq -nc --arg u "$url" --arg m "$method" '{url:$u,method:$m}')
    # Copilot CLI sends camelCase: WebFetch → webFetch, WebSearch → webSearch
    local copilot_tool
    copilot_tool="$(echo "${tool:0:1}" | tr '[:upper:]' '[:lower:]')${tool:1}"
    payload=$(jq -nc --arg t "$copilot_tool" --arg a "$args_json" '{toolName:$t,toolArgs:$a}')
  else
    payload=$(jq -nc --arg t "$tool" --arg u "$url" --arg m "$method" \
      '{tool_name:$t,tool_input:{url:$u,method:$m}}')
  fi

  raw=$(echo "$payload" | bash "$HOOK_SCRIPT" 2>/dev/null) || true
  if [[ -z "$raw" ]]; then
    result="none"
  elif [[ "$format" == "copilot" ]]; then
    result=$(echo "$raw" | jq -r '.permissionDecision // "none"')
  else
    result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  fi

  # Copilot CLI has no "ask" — maps to deny
  local effective_expected="$expected"
  if [[ "$format" == "copilot" && "$expected" == "ask" ]]; then
    effective_expected="deny"
  fi

  if [[ "$result" == "$effective_expected" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "$expected" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "$expected" "$label" "$result"
    ((FAIL++)) || true
  fi
}

run_test_search() {
  local expected="$1" label="${2:-WebSearch}" format="${3:-claude}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local payload raw result
  if [[ "$format" == "copilot" ]]; then
    local args_json
    args_json=$(jq -nc '{query:"test query"}')
    payload=$(jq -nc --arg a "$args_json" '{toolName:"webSearch",toolArgs:$a}')
  else
    payload=$(jq -nc '{tool_name:"WebSearch",tool_input:{query:"test query"}}')
  fi

  raw=$(echo "$payload" | bash "$HOOK_SCRIPT" 2>/dev/null) || true
  if [[ -z "$raw" ]]; then
    result="none"
  elif [[ "$format" == "copilot" ]]; then
    result=$(echo "$raw" | jq -r '.permissionDecision // "none"')
  else
    result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  fi

  if [[ "$result" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "$expected" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "$expected" "$label" "$result"
    ((FAIL++)) || true
  fi
}

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq is required"
  exit 0
fi

# =========================================================================
#  MODE: off (default — passthrough)
# =========================================================================
echo "── Mode: off (passthrough) ──"

reset_config
run_test "none" "WebFetch" "https://example.com/page" "off → WebFetch passthrough"
run_test_search "none" "off → WebSearch passthrough"

# Explicitly set off
reset_config
write_global '{"mode":"off","domains":[]}'
run_test "none" "WebFetch" "https://example.com/page" "off explicit → WebFetch passthrough"

# =========================================================================
#  MODE: all
# =========================================================================
echo "── Mode: all ──"

reset_config
write_global '{"mode":"all","domains":[]}'

run_test "allow" "WebFetch" "https://example.com/page" "all → allow GET"
run_test "allow" "WebFetch" "https://any-domain.io/api" "all → allow GET any domain"
run_test "ask" "WebFetch" "https://example.com/api" "all → ask POST" "claude" "POST"
run_test "ask" "WebFetch" "https://example.com/api" "all → ask PUT" "claude" "PUT"
run_test "ask" "WebFetch" "https://example.com/api" "all → ask DELETE" "claude" "DELETE"
run_test "ask" "WebFetch" "https://example.com/api" "all → ask PATCH" "claude" "PATCH"
run_test_search "allow" "all → WebSearch allowed"

# =========================================================================
#  MODE: domains
# =========================================================================
echo "── Mode: domains ──"

reset_config
write_global '{"mode":"domains","domains":["github.com","docs.anthropic.com"]}'

run_test "allow" "WebFetch" "https://github.com/org/repo" "domains → allow matched domain"
run_test "allow" "WebFetch" "https://api.github.com/repos" "domains → allow subdomain match"
run_test "allow" "WebFetch" "https://docs.anthropic.com/guide" "domains → allow second domain"
run_test "ask" "WebFetch" "https://evil.com/hack" "domains → ask unmatched domain"
run_test "ask" "WebFetch" "https://notgithub.com/page" "domains → ask partial mismatch"
run_test "ask" "WebFetch" "https://github.com/api" "domains → ask POST even if domain matched" "claude" "POST"
run_test_search "allow" "domains → WebSearch allowed"

# =========================================================================
#  Bypass permissions
# =========================================================================
echo "── Bypass permissions ──"

reset_config
write_global '{"mode":"domains","domains":["github.com"]}'

# Claude bypass
if [[ -n "$FILTER" ]] && ! echo "bypass → passthrough" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  local_payload=$(jq -nc '{tool_name:"WebFetch",tool_input:{url:"https://evil.com"},permission_mode:"bypassPermissions"}')
  raw=$(echo "$local_payload" | bash "$HOOK_SCRIPT" 2>/dev/null) || true
  if [[ -z "$raw" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "none" "bypass → passthrough"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got output)\n" "none" "bypass → passthrough"
    ((FAIL++)) || true
  fi
fi

# Copilot bypass
if [[ -n "$FILTER" ]] && ! echo "bypass → passthrough [copilot]" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  local_args=$(jq -nc '{url:"https://evil.com"}')
  local_payload=$(jq -nc --arg a "$local_args" '{toolName:"webfetch",toolArgs:$a}')
  raw=$(COPILOT_ALLOW_ALL=true bash -c "echo '$local_payload' | bash '$HOOK_SCRIPT'" 2>/dev/null) || true
  if [[ -z "$raw" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "none" "bypass → passthrough [copilot]"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got output)\n" "none" "bypass → passthrough [copilot]"
    ((FAIL++)) || true
  fi
fi

# =========================================================================
#  Copilot format payloads
# =========================================================================
echo "── Copilot format ──"

reset_config
write_global '{"mode":"all","domains":[]}'

run_test "allow" "WebFetch" "https://example.com/page" "copilot → allow GET" "copilot"
run_test "ask" "WebFetch" "https://example.com/api" "copilot → ask POST" "copilot" "POST"
run_test_search "allow" "copilot → WebSearch allowed" "copilot"

reset_config
write_global '{"mode":"domains","domains":["github.com"]}'

run_test "allow" "WebFetch" "https://github.com/repo" "copilot domains → allow matched" "copilot"
run_test "ask" "WebFetch" "https://evil.com/page" "copilot domains → ask unmatched" "copilot"

# =========================================================================
#  Config scoping: project mode overrides global; domains merge
# =========================================================================
echo "── Config scoping ──"

reset_config
write_global '{"mode":"all","domains":[]}'
write_project '{"mode":"domains","domains":["project-only.com"]}'

run_test "allow" "WebFetch" "https://project-only.com/page" "project mode overrides global → domains mode"
run_test "ask" "WebFetch" "https://random.com/page" "project mode overrides global → ask unmatched"

# Domains merge across scopes
reset_config
write_global '{"mode":"domains","domains":["github.com"]}'
write_project '{"mode":"domains","domains":["docs.anthropic.com"]}'

run_test "allow" "WebFetch" "https://github.com/repo" "domains merge → global domain"
run_test "allow" "WebFetch" "https://docs.anthropic.com/guide" "domains merge → project domain"
run_test "ask" "WebFetch" "https://other.com/page" "domains merge → ask unmatched"

# Project off overrides global all
reset_config
write_global '{"mode":"all","domains":[]}'
write_project '{"mode":"off","domains":[]}'

run_test "none" "WebFetch" "https://example.com/page" "project off overrides global all"

# =========================================================================
#  Non-web tools are ignored (passthrough)
# =========================================================================
echo "── Non-web tools ignored ──"

reset_config
write_global '{"mode":"all","domains":[]}'

if [[ -n "$FILTER" ]] && ! echo "Bash tool → passthrough" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  local_payload=$(jq -nc '{tool_name:"Bash",tool_input:{command:"ls"}}')
  raw=$(echo "$local_payload" | bash "$HOOK_SCRIPT" 2>/dev/null) || true
  if [[ -z "$raw" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "none" "Bash tool → passthrough"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got output)\n" "none" "Bash tool → passthrough"
    ((FAIL++)) || true
  fi
fi

# =========================================================================
#  manage-custom-patterns.sh --type web
# =========================================================================
echo "── manage-custom-patterns.sh --type web ──"

reset_config

# set-mode
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" set-mode --type web --scope global all 2>&1)
if echo "$TEST_OUTPUT" | grep -q "Set global mode: all"; then
  printf "  \033[32m✓\033[0m set-mode global all\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m set-mode global all  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# Verify mode was written
ACTUAL_MODE=$(jq -r '.mode' "$WEB_PERMISSIONS_GLOBAL" 2>/dev/null)
if [[ "$ACTUAL_MODE" == "all" ]]; then
  printf "  \033[32m✓\033[0m mode persisted in config file\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m mode persisted in config file  (got: %s)\n" "$ACTUAL_MODE"
  ((FAIL++)) || true
fi

# add domain
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" add --type web --scope global github.com 2>&1)
if echo "$TEST_OUTPUT" | grep -q "Added to global: github.com"; then
  printf "  \033[32m✓\033[0m add domain\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m add domain  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# add duplicate
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" add --type web --scope global github.com 2>&1)
if echo "$TEST_OUTPUT" | grep -q "already exists"; then
  printf "  \033[32m✓\033[0m add duplicate → already exists\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m add duplicate  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# list
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" list --type web 2>&1)
if echo "$TEST_OUTPUT" | grep -q "github.com" && echo "$TEST_OUTPUT" | grep -q "mode: all"; then
  printf "  \033[32m✓\033[0m list shows mode and domain\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m list  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# remove domain
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" remove --type web --scope global github.com 2>&1)
if echo "$TEST_OUTPUT" | grep -q "Removed from global: github.com"; then
  printf "  \033[32m✓\033[0m remove domain\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m remove domain  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# remove nonexistent
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" remove --type web --scope global nonexistent.com 2>&1)
if echo "$TEST_OUTPUT" | grep -q "not found"; then
  printf "  \033[32m✓\033[0m remove nonexistent → not found\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m remove nonexistent  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# invalid mode
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" set-mode --type web --scope global invalid 2>&1) || true
if echo "$TEST_OUTPUT" | grep -q "must be"; then
  printf "  \033[32m✓\033[0m set-mode invalid → error\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m set-mode invalid  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# set-mode on non-web type → error
TEST_OUTPUT=$(bash "$MANAGE_SCRIPT" set-mode --type commands --scope global all 2>&1) || true
if echo "$TEST_OUTPUT" | grep -q "only valid with --type web"; then
  printf "  \033[32m✓\033[0m set-mode on commands type → error\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m set-mode on commands type  (got: %s)\n" "$TEST_OUTPUT"
  ((FAIL++)) || true
fi

# =========================================================================
#  URL edge cases
# =========================================================================
echo "── URL edge cases ──"

reset_config
write_global '{"mode":"domains","domains":["example.com"]}'

run_test "allow" "WebFetch" "https://example.com:8080/path" "domain with port → match"
run_test "allow" "WebFetch" "https://example.com/path?q=1#frag" "domain with query+fragment → match"
run_test "allow" "WebFetch" "https://sub.example.com/path" "subdomain → match"
run_test "ask" "WebFetch" "https://notexample.com/path" "suffix mismatch → ask"

# HEAD method should be allowed like GET
run_test "allow" "WebFetch" "https://example.com/page" "HEAD method → allow" "claude" "HEAD"

# ===== Summary =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
if [[ $SKIP -gt 0 ]]; then
  printf "  \033[33m%d skipped\033[0m" "$SKIP"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
