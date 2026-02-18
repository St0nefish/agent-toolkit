#!/usr/bin/env bash
# Tests for deploy.sh hook registration into settings.json
# Run from repo root: bash tests/test-deploy-hooks.sh
#
# Uses CLAUDE_CONFIG_DIR pointed at a temp directory — never touches real config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$REPO_DIR/deploy.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Portable md5 helper (Linux md5sum vs macOS md5)
file_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -d' ' -f1
    else
        md5 -q "$1"
    fi
}

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
export CLAUDE_CONFIG_DIR="$TESTDIR"
echo "Using TESTDIR=$TESTDIR"

# Seed settings.json with other keys to verify preservation
mkdir -p "$TESTDIR"
cat > "$TESTDIR/settings.json" << 'EOF'
{
  "env": {"TEST": "preserved"},
  "model": "test-model"
}
EOF

# ===== Test: deploy writes hooks object =====
echo ""
echo "=== Test: deploy writes hooks object ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" 2>&1) || true

if jq -e '.hooks | type == "object"' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "hooks is an object"
else
    fail "hooks is an object" "missing or wrong type"
fi

# ===== Test: PreToolUse hook present =====
echo ""
echo "=== Test: PreToolUse hook ==="
pre_count=$(jq '.hooks.PreToolUse | length' "$TESTDIR/settings.json" 2>/dev/null || echo 0)
if [[ "$pre_count" -gt 0 ]]; then
    pass "PreToolUse has entries ($pre_count)"
else
    fail "PreToolUse has entries" "count=$pre_count"
fi

pre_matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if [[ "$pre_matcher" == "Bash" ]]; then
    pass "PreToolUse matcher is Bash"
else
    fail "PreToolUse matcher is Bash" "got '$pre_matcher'"
fi

pre_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if echo "$pre_cmd" | grep -q 'bash-safety/bash-safety.sh$'; then
    pass "PreToolUse command points to bash-safety.sh"
else
    fail "PreToolUse command points to bash-safety.sh" "got '$pre_cmd'"
fi

pre_type=$(jq -r '.hooks.PreToolUse[0].hooks[0].type' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if [[ "$pre_type" == "command" ]]; then
    pass "PreToolUse hook type is command"
else
    fail "PreToolUse hook type is command" "got '$pre_type'"
fi

# PreToolUse should NOT have async
pre_async=$(jq -r '.hooks.PreToolUse[0].hooks[0].async // "absent"' "$TESTDIR/settings.json" 2>/dev/null || echo "absent")
if [[ "$pre_async" == "absent" || "$pre_async" == "false" ]]; then
    pass "PreToolUse has no async flag"
else
    fail "PreToolUse has no async flag" "got '$pre_async'"
fi

# ===== Test: PostToolUse hook present =====
echo ""
echo "=== Test: PostToolUse hook ==="
post_count=$(jq '.hooks.PostToolUse | length' "$TESTDIR/settings.json" 2>/dev/null || echo 0)
if [[ "$post_count" -gt 0 ]]; then
    pass "PostToolUse has entries ($post_count)"
else
    fail "PostToolUse has entries" "count=$post_count"
fi

post_matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if [[ "$post_matcher" == "Edit|Write" ]]; then
    pass "PostToolUse matcher is Edit|Write"
else
    fail "PostToolUse matcher is Edit|Write" "got '$post_matcher'"
fi

post_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if echo "$post_cmd" | grep -q 'format-on-save/format-on-save.sh$'; then
    pass "PostToolUse command points to format-on-save.sh"
else
    fail "PostToolUse command points to format-on-save.sh" "got '$post_cmd'"
fi

post_async=$(jq -r '.hooks.PostToolUse[0].hooks[0].async' "$TESTDIR/settings.json" 2>/dev/null || echo "false")
if [[ "$post_async" == "true" ]]; then
    pass "PostToolUse has async=true"
else
    fail "PostToolUse has async=true" "got '$post_async'"
fi

post_timeout=$(jq -r '.hooks.PostToolUse[0].hooks[0].timeout' "$TESTDIR/settings.json" 2>/dev/null || echo "")
if [[ "$post_timeout" == "60" ]]; then
    pass "PostToolUse has timeout=60"
else
    fail "PostToolUse has timeout=60" "got '$post_timeout'"
fi

# ===== Test: other keys preserved =====
echo ""
echo "=== Test: other keys preserved ==="
env_test=$(jq -r '.env.TEST' "$TESTDIR/settings.json")
if [[ "$env_test" == "preserved" ]]; then
    pass "env.TEST preserved"
else
    fail "env.TEST preserved" "got '$env_test'"
fi

model_val=$(jq -r '.model' "$TESTDIR/settings.json")
if [[ "$model_val" == "test-model" ]]; then
    pass "model preserved"
else
    fail "model preserved" "got '$model_val'"
fi

# ===== Test: idempotency =====
echo ""
echo "=== Test: idempotency ==="
md5_before=$(file_md5 "$TESTDIR/settings.json")
output2=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" 2>&1) || true
md5_after=$(file_md5 "$TESTDIR/settings.json")

if [[ "$md5_before" == "$md5_after" ]]; then
    pass "idempotent (md5 unchanged)"
else
    fail "idempotent (md5 unchanged)" "md5 changed"
fi

# ===== Test: append-missing preserves manual hooks =====
echo ""
echo "=== Test: append-missing preserves manual hooks ==="

# Inject a custom hook event+matcher
existing=$(cat "$TESTDIR/settings.json")
echo "$existing" | jq '.hooks.CustomEvent = [{"matcher": "Read", "hooks": [{"type": "command", "command": "/usr/bin/true"}]}]' > "$TESTDIR/settings.json"

if jq -e '.hooks.CustomEvent' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "custom hook injected"
else
    fail "custom hook injected" "injection failed"
fi

# Re-deploy — custom hook should survive
output4=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" 2>&1) || true

if jq -e '.hooks.CustomEvent' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "append-missing preserves custom hook event"
else
    fail "append-missing preserves custom hook event" "CustomEvent was removed"
fi

# Original deploy hooks should still be present
if jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "deploy hooks still present after append"
else
    fail "deploy hooks still present after append" "PreToolUse Bash matcher missing"
fi

# ===== Test: --skip-permissions skips hooks too =====
echo ""
echo "=== Test: --skip-permissions skips hooks ==="
# Seed with different hooks to detect if they get overwritten
existing=$(cat "$TESTDIR/settings.json")
echo "$existing" | jq '.hooks = {"Fake": []}' > "$TESTDIR/settings.json"
md5_before=$(file_md5 "$TESTDIR/settings.json")

output3=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" --skip-permissions 2>&1) || true
md5_after=$(file_md5 "$TESTDIR/settings.json")

if echo "$output3" | grep -q 'Skipped: hooks management'; then
    pass "--skip-permissions skips hooks message"
else
    fail "--skip-permissions skips hooks message" "expected skip message in output"
fi

# Hooks should NOT have been updated (still "Fake")
if jq -e '.hooks.Fake' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "--skip-permissions hooks unchanged"
else
    fail "--skip-permissions hooks unchanged" "hooks were overwritten"
fi

echo ""
echo "=============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
