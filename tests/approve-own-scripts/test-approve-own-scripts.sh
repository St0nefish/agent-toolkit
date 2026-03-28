#!/usr/bin/env bash
# test-approve-own-scripts.sh — Test harness for approve-own-scripts.sh hook.
# Verifies that the hook auto-allows plugin scripts and falls through for others.
#
# Usage: bash tests/approve-own-scripts/test-approve-own-scripts.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../utils/approve-own-scripts.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# Simulated plugin root for testing
FAKE_PLUGIN_ROOT="/home/user/.claude/plugins/marketplaces/agent-toolkit/plugins-claude/git-cli"

run_test() {
  local expected="$1" command="$2" label="${3:-$2}" format="${4:-claude}" plugin_root="${5:-$FAKE_PLUGIN_ROOT}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local payload raw result
  if [[ "$format" == "copilot" ]]; then
    local args_json
    args_json=$(jq -n --arg c "$command" '{"command":$c}' | jq -c '.')
    payload=$(jq -n --arg t "bash" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}')
  else
    payload=$(jq -n --arg t "Bash" --arg c "$command" \
      '{tool_name:$t,tool_input:{command:$c},hook_event_name:"PreToolUse",permission_mode:"default"}')
  fi

  local env_var="CLAUDE_PLUGIN_ROOT"
  [[ "$format" == "copilot" ]] && env_var="COPILOT_PLUGIN_ROOT"

  raw=$(echo "$payload" | env -i HOME="$HOME" PATH="$PATH" "$env_var=$plugin_root" bash "$HOOK_SCRIPT" 2>/dev/null) || true

  if [[ -z "$raw" ]]; then
    result="none"
  elif [[ "$format" == "copilot" ]]; then
    result=$(echo "$raw" | jq -r '.permissionDecision // "none"')
  else
    result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  fi

  if [[ "$result" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: %s, got: %s)\n" "$label" "$expected" "$result"
    ((FAIL++)) || true
  fi
}

run_test_both() {
  local expected="$1" command="$2" label="${3:-$2}" plugin_root="${4:-$FAKE_PLUGIN_ROOT}"
  run_test "$expected" "$command" "$label" "claude" "$plugin_root"
  run_test "$expected" "$command" "$label [copilot]" "copilot" "$plugin_root"
}

# ===== ALLOW: plugin's own scripts =====
echo "── Direct script execution ──"
run_test_both allow \
  "$FAKE_PLUGIN_ROOT/scripts/git-cli run list --branch main --limit 1" \
  "direct: git-cli with args"

run_test_both allow \
  "$FAKE_PLUGIN_ROOT/scripts/git-cli" \
  "direct: git-cli no args"

run_test_both allow \
  "$FAKE_PLUGIN_ROOT/scripts/some-script.sh --flag value" \
  "direct: arbitrary script with args"

echo "── bash/sh prefix ──"
run_test_both allow \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli run list --limit 1" \
  "bash prefix: git-cli"

run_test_both allow \
  "sh $FAKE_PLUGIN_ROOT/scripts/setup.sh" \
  "sh prefix: setup.sh"

run_test_both allow \
  "bash $FAKE_PLUGIN_ROOT/scripts/hook-compat.sh" \
  "bash prefix: hook-compat.sh"

# ===== NONE (fall-through): non-plugin commands =====
echo "── Non-plugin commands (fall-through) ──"
run_test_both none \
  "rm -rf /" \
  "destructive: rm -rf"

run_test_both none \
  "echo hello" \
  "benign: echo"

run_test_both none \
  "ls -la" \
  "read-only: ls"

run_test_both none \
  "curl https://example.com" \
  "network: curl"

run_test_both none \
  "git status" \
  "git: status"

# ===== NONE (fall-through): other plugin paths =====
echo "── Other plugin paths (fall-through) ──"
OTHER_PLUGIN="/home/user/.claude/plugins/marketplaces/agent-toolkit/plugins-claude/session"
run_test_both none \
  "$OTHER_PLUGIN/scripts/catchup" \
  "different plugin's script" \
  "$FAKE_PLUGIN_ROOT"

run_test_both none \
  "/home/user/malicious/scripts/evil.sh" \
  "non-plugin path"

run_test_both none \
  "/home/user/.claude/plugins/marketplaces/agent-toolkit/plugins-claude/git-cli/NOT-scripts/foo" \
  "plugin root but not scripts/"

# ===== NONE (fall-through): partial path match attacks =====
echo "── Path traversal / partial match ──"
run_test_both none \
  "$FAKE_PLUGIN_ROOT/scripts/../../../etc/passwd" \
  "path traversal with .."

run_test_both none \
  "${FAKE_PLUGIN_ROOT}-evil/scripts/steal-data" \
  "suffix-appended plugin root"

# ===== Edge cases =====
echo "── Edge cases ──"
run_test_both none \
  "" \
  "empty command"

run_test_both allow \
  "$FAKE_PLUGIN_ROOT/scripts/script with spaces" \
  "script path with spaces"

# Test with no PLUGIN_ROOT set (should fall through)
echo "── No PLUGIN_ROOT set ──"
payload_claude=$(jq -n --arg t "Bash" --arg c "$FAKE_PLUGIN_ROOT/scripts/git-cli run list" \
  '{tool_name:$t,tool_input:{command:$c},hook_event_name:"PreToolUse",permission_mode:"default"}')
raw=$(echo "$payload_claude" | env -i HOME="$HOME" PATH="$PATH" bash "$HOOK_SCRIPT" 2>/dev/null) || true
if [[ -z "$raw" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "no CLAUDE_PLUGIN_ROOT → fall-through"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected: none, got output)\n" "no CLAUDE_PLUGIN_ROOT → fall-through"
  ((FAIL++)) || true
fi

args_json=$(jq -n --arg c "$FAKE_PLUGIN_ROOT/scripts/git-cli run list" '{"command":$c}' | jq -c '.')
payload_copilot=$(jq -n --arg t "bash" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}')
raw=$(echo "$payload_copilot" | env -i HOME="$HOME" PATH="$PATH" bash "$HOOK_SCRIPT" 2>/dev/null) || true
if [[ -z "$raw" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "no COPILOT_PLUGIN_ROOT → fall-through"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected: none, got output)\n" "no COPILOT_PLUGIN_ROOT → fall-through"
  ((FAIL++)) || true
fi

# ===== Non-Bash tool (should fall through) =====
echo "── Non-Bash tool ──"
payload=$(jq -n '{tool_name:"Edit",tool_input:{file_path:"/tmp/foo"},hook_event_name:"PreToolUse",permission_mode:"default"}')
raw=$(echo "$payload" | env -i HOME="$HOME" PATH="$PATH" CLAUDE_PLUGIN_ROOT="$FAKE_PLUGIN_ROOT" bash "$HOOK_SCRIPT" 2>/dev/null) || true
if [[ -z "$raw" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "Edit tool → fall-through"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected: none, got output)\n" "Edit tool → fall-through"
  ((FAIL++)) || true
fi

# ===== Summary =====
echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
