#!/usr/bin/env bash
# Tests for hooks/notify-on-stop/notify-on-stop.sh
# Run from repo root: bash tests/test-notify-on-stop-hook.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/hooks/notify-on-stop/notify-on-stop.sh"

PASS=0 FAIL=0

# Override PATH so osascript/notify-send aren't found (no real notifications)
SAFE_PATH="/usr/bin:/bin"

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — got '$actual', expected '$expected'"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test: UserPromptSubmit creates state file
# ---------------------------------------------------------------------------
echo "=== UserPromptSubmit creates state file ==="
test_session="test-$$-submit"
state_file="/tmp/claude-notify-${test_session}"
rm -f "$state_file"

json=$(jq -n --arg sid "$test_session" '{hook_event_name: "UserPromptSubmit", session_id: $sid}')
echo "$json" | PATH="$SAFE_PATH" bash "$HOOK" 2>/dev/null
assert_eq "state file created" "$(test -f "$state_file" && echo yes || echo no)" "yes"
assert_eq "state file contains epoch" "$(cat "$state_file" | grep -cE '^[0-9]+$')" "1"
rm -f "$state_file"

# ---------------------------------------------------------------------------
# Test: Stop with elapsed > threshold fires (notification binary missing → ok)
# ---------------------------------------------------------------------------
echo ""
echo "=== Stop with elapsed > threshold ==="
test_session="test-$$-over"
state_file="/tmp/claude-notify-${test_session}"
# Write a start epoch 60 seconds in the past
echo $(( $(date +%s) - 60 )) > "$state_file"

json=$(jq -n --arg sid "$test_session" '{
  hook_event_name: "Stop",
  session_id: $sid,
  cwd: "/home/user/my-project",
  last_assistant_message: "Done with the refactoring task"
}')
output=$(echo "$json" | PATH="$SAFE_PATH" CLAUDE_NOTIFY_MIN_SECONDS=30 bash "$HOOK" 2>&1) || true
rc=$?
assert_eq "exit code 0" "$rc" "0"
assert_eq "state file cleaned up" "$(test -f "$state_file" && echo exists || echo gone)" "gone"

# ---------------------------------------------------------------------------
# Test: Stop with elapsed < threshold — no notification
# ---------------------------------------------------------------------------
echo ""
echo "=== Stop with elapsed < threshold ==="
test_session="test-$$-under"
state_file="/tmp/claude-notify-${test_session}"
# Write a start epoch 5 seconds in the past
echo $(( $(date +%s) - 5 )) > "$state_file"

json=$(jq -n --arg sid "$test_session" '{hook_event_name: "Stop", session_id: $sid}')
echo "$json" | PATH="$SAFE_PATH" CLAUDE_NOTIFY_MIN_SECONDS=30 bash "$HOOK" 2>/dev/null
rc=$?
assert_eq "exit code 0" "$rc" "0"
assert_eq "state file cleaned up" "$(test -f "$state_file" && echo exists || echo gone)" "gone"

# ---------------------------------------------------------------------------
# Test: Stop with stop_hook_active: true — exits immediately
# ---------------------------------------------------------------------------
echo ""
echo "=== Stop with stop_hook_active: true ==="
test_session="test-$$-active"
state_file="/tmp/claude-notify-${test_session}"
echo $(( $(date +%s) - 60 )) > "$state_file"

json=$(jq -n --arg sid "$test_session" '{
  hook_event_name: "Stop",
  session_id: $sid,
  stop_hook_active: true
}')
echo "$json" | PATH="$SAFE_PATH" bash "$HOOK" 2>/dev/null
rc=$?
assert_eq "exit code 0" "$rc" "0"
assert_eq "state file NOT cleaned up" "$(test -f "$state_file" && echo exists || echo gone)" "exists"
rm -f "$state_file"

# ---------------------------------------------------------------------------
# Test: Stop with no state file — graceful exit
# ---------------------------------------------------------------------------
echo ""
echo "=== Stop with no state file ==="
test_session="test-$$-nofile"
state_file="/tmp/claude-notify-${test_session}"
rm -f "$state_file"

json=$(jq -n --arg sid "$test_session" '{hook_event_name: "Stop", session_id: $sid}')
echo "$json" | PATH="$SAFE_PATH" bash "$HOOK" 2>/dev/null
rc=$?
assert_eq "exit code 0" "$rc" "0"

# ---------------------------------------------------------------------------
# Test: Unknown event — no side effects
# ---------------------------------------------------------------------------
echo ""
echo "=== Unknown event ==="
test_session="test-$$-unknown"
state_file="/tmp/claude-notify-${test_session}"
rm -f "$state_file"

json=$(jq -n --arg sid "$test_session" '{hook_event_name: "SomeOtherEvent", session_id: $sid}')
echo "$json" | PATH="$SAFE_PATH" bash "$HOOK" 2>/dev/null
rc=$?
assert_eq "exit code 0" "$rc" "0"
assert_eq "no state file created" "$(test -f "$state_file" && echo exists || echo gone)" "gone"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
