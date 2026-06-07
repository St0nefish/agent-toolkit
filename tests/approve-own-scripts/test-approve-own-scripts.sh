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
FAKE_PLUGIN_ROOT="/home/user/.claude/plugins/marketplaces/agent-toolkit/plugins-claude/git-tools"

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

# Expects an "ask" decision on Claude Code; on Copilot CLI there is no "ask", so
# hook_ask degrades to a hard "deny".
run_test_ask() {
  local command="$1" label="${2:-$1}" plugin_root="${3:-$FAKE_PLUGIN_ROOT}"
  run_test ask "$command" "$label" "claude" "$plugin_root"
  run_test deny "$command" "$label [copilot]" "copilot" "$plugin_root"
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

# ===== ASK: outward PR publish guard (create/merge a PR) =====
# Must fire whether the PR is opened/merged via the plugin's own git-cli wrapper
# OR a direct gh/tea invocation that would sidestep the wrapper.
echo "── PR publish guard (must ASK) ──"
run_test_ask \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli pr create --title x --body y" \
  "git-cli pr create"

run_test_ask \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli pr merge 5 --squash" \
  "git-cli pr merge"

run_test_ask \
  "gh pr create --fill" \
  "direct gh pr create (sidestep)"

run_test_ask \
  "tea pr create" \
  "direct tea pr create (sidestep)"

run_test_ask \
  "gh pr merge 42 --squash" \
  "direct gh pr merge (sidestep)"

# Guard must NOT fire on read-only or reversible pr ops.
echo "── PR guard must NOT fire (read-only / reversible) ──"
run_test_both allow \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli pr auto-merge-status --branch main" \
  "git-cli pr auto-merge-status (read-only → own-script allow)"

run_test_both allow \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli pr close 5" \
  "git-cli pr close (reversible → own-script allow)"

run_test_both allow \
  "bash $FAKE_PLUGIN_ROOT/scripts/git-cli pr list --state open" \
  "git-cli pr list (read-only → own-script allow)"

run_test_both none \
  "gh pr view 3" \
  "gh pr view (not own script, not publish)"

run_test_both none \
  "gh pr list" \
  "gh pr list (not own script, not publish)"

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
  "/home/user/.claude/plugins/marketplaces/agent-toolkit/plugins-claude/git-tools/NOT-scripts/foo" \
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

# The PR-publish guard runs BEFORE the PLUGIN_ROOT check, so it must still fire
# even with no plugin root set (guards against a future reorg that moves it).
payload_claude=$(jq -n --arg t "Bash" --arg c "gh pr create --fill" \
  '{tool_name:$t,tool_input:{command:$c},hook_event_name:"PreToolUse",permission_mode:"default"}')
raw=$(echo "$payload_claude" | env -i HOME="$HOME" PATH="$PATH" bash "$HOOK_SCRIPT" 2>/dev/null) || true
result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "none")
if [[ "$result" == "ask" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "PR guard fires with no PLUGIN_ROOT → ask"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected: ask, got: %s)\n" "PR guard fires with no PLUGIN_ROOT → ask" "$result"
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

# ===== Read/Glob/Grep: auto-approve reads of the plugin's own bundled files =====
# Read carries the target in file_path; Glob/Grep use path. The hook allows any
# target under the plugin root and falls through otherwise.
#
# run_read_test EXPECTED TOOL FIELD VALUE [FORMAT] [PLUGIN_ROOT]
run_read_test() {
  # Note: ${6-default} (no colon) so an explicit empty arg stays empty — that's
  # how the "no plugin root → defer" case is exercised.
  local expected="$1" tool="$2" field="$3" value="$4" format="${5:-claude}" plugin_root="${6-$FAKE_PLUGIN_ROOT}"
  local label="$tool $field=$value"
  label="$label${format:+ [$format]}"
  [[ "$format" == "claude" ]] && label="$tool $field=$value"

  local payload raw result env_var="CLAUDE_PLUGIN_ROOT"
  if [[ "$format" == "copilot" ]]; then
    env_var="COPILOT_PLUGIN_ROOT"
    local args_json
    args_json=$(jq -n --arg f "$field" --arg v "$value" '{($f):$v}' | jq -c '.')
    payload=$(jq -n --arg t "${tool,,}" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}')
  else
    payload=$(jq -n --arg t "$tool" --arg f "$field" --arg v "$value" \
      '{tool_name:$t,tool_input:{($f):$v},hook_event_name:"PreToolUse",permission_mode:"default"}')
  fi

  local cmd_env=(env -i HOME="$HOME" PATH="$PATH")
  [[ -n "$plugin_root" ]] && cmd_env+=("$env_var=$plugin_root")
  raw=$(echo "$payload" | "${cmd_env[@]}" bash "$HOOK_SCRIPT" 2>/dev/null) || true

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

echo "── Read/Glob/Grep own files (must ALLOW) ──"
run_read_test allow Read file_path "$FAKE_PLUGIN_ROOT/reference/spine.md"
run_read_test allow Read file_path "$FAKE_PLUGIN_ROOT/reference/spine.md" copilot
run_read_test allow Read file_path "$FAKE_PLUGIN_ROOT/skills/foo/SKILL.md"
run_read_test allow Glob path "$FAKE_PLUGIN_ROOT/reference"
run_read_test allow Grep path "$FAKE_PLUGIN_ROOT/scripts"
run_read_test allow Grep path "$FAKE_PLUGIN_ROOT/scripts" copilot

echo "── Read/Glob/Grep other paths (fall-through) ──"
run_read_test none Read file_path "/data/workspace/project/CLAUDE.md"
run_read_test none Read file_path "/data/workspace/project/CLAUDE.md" copilot
run_read_test none Read file_path "${FAKE_PLUGIN_ROOT}-evil/secret"
run_read_test none Read file_path "$FAKE_PLUGIN_ROOT/../../../etc/passwd"
run_read_test none Grep path "/etc"
# A pathless Grep (project-wide search) must defer, not blanket-allow.
run_read_test none Grep pattern "TODO"
# No plugin root → can't classify ownership → defer.
run_read_test none Read file_path "$FAKE_PLUGIN_ROOT/reference/spine.md" claude ""

# ===== Summary =====
echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
