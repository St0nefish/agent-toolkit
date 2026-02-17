#!/usr/bin/env bash
# Tests for deploy.sh permission management
# Run from repo root: bash tests/test-deploy-permissions.sh
#
# Uses CLAUDE_CONFIG_DIR pointed at a temp directory — never touches real config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$REPO_DIR/deploy.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Create isolated temp dir
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
export CLAUDE_CONFIG_DIR="$TESTDIR"
echo "Using TESTDIR=$TESTDIR"

# Seed fake settings.json with other keys to verify preservation
mkdir -p "$TESTDIR"
cat > "$TESTDIR/settings.json" << 'EOF'
{
  "env": {"TEST": "preserved"},
  "model": "test-model",
  "hooks": {"PreToolUse": []}
}
EOF

SEED_MD5=$(md5sum "$TESTDIR/settings.json" | cut -d' ' -f1)

# ===== Test: dry-run with --skip-permissions =====
echo ""
echo "=== Test: dry-run ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" --dry-run --skip-permissions 2>&1) || true

if [[ -f "$TESTDIR/settings.json.tmp" ]]; then
    fail "dry-run no tmp file" "settings.json.tmp was created"
else
    pass "dry-run no tmp file"
fi

current_md5=$(md5sum "$TESTDIR/settings.json" | cut -d' ' -f1)
if [[ "$current_md5" == "$SEED_MD5" ]]; then
    pass "dry-run settings.json unchanged"
else
    fail "dry-run settings.json unchanged" "md5 changed"
fi

# ===== Test: actual deploy =====
echo ""
echo "=== Test: actual deploy ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" 2>&1) || true

if echo "$output" | grep -q 'Updated:.*permissions.*allow entries'; then
    pass "output mentions Updated with count"
else
    fail "output mentions Updated with count" "no matching line"
fi

if jq -e '.permissions.allow | type == "array"' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "permissions.allow is array"
else
    fail "permissions.allow is array" "missing or wrong type"
fi

if jq -e '.permissions.allow | index("Bash(jar-explore)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "contains Bash(jar-explore)"
else
    fail "contains Bash(jar-explore)" "not found"
fi

if jq -e '.permissions.allow | index("Bash(jar-explore *)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "contains Bash(jar-explore *)"
else
    fail "contains Bash(jar-explore *)" "not found"
fi

if jq -e '.permissions.allow | index("Bash(find)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "contains Bash(find)"
else
    fail "contains Bash(find)" "not found"
fi

if jq -e '.permissions.allow | index("Bash(ls *)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "contains Bash(ls *)"
else
    fail "contains Bash(ls *)" "not found"
fi

git_entries=$(jq -r '.permissions.allow[]' "$TESTDIR/settings.json" | grep '^Bash(git ' || true)
if [[ -z "$git_entries" ]]; then
    pass "no Bash(git ...) entries"
else
    fail "no Bash(git ...) entries" "found: $git_entries"
fi

wf_count=$(jq '[.permissions.allow[] | select(startswith("WebFetch("))] | length' "$TESTDIR/settings.json")
if [[ "$wf_count" -gt 0 ]]; then
    pass "contains WebFetch entries ($wf_count)"
else
    fail "contains WebFetch entries" "none found"
fi

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

if jq -e '.hooks' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "hooks key preserved"
else
    fail "hooks key preserved" "hooks key missing"
fi

deny_len=$(jq '.permissions.deny | length' "$TESTDIR/settings.json")
if [[ "$deny_len" == "0" ]]; then
    pass "permissions.deny is empty array"
else
    fail "permissions.deny is empty array" "length=$deny_len"
fi

sorted=$(jq -r '.permissions.allow[]' "$TESTDIR/settings.json" | sort)
actual=$(jq -r '.permissions.allow[]' "$TESTDIR/settings.json")
if [[ "$sorted" == "$actual" ]]; then
    pass "allow array is sorted"
else
    fail "allow array is sorted" "not in sorted order"
fi

# ===== Test: idempotency =====
echo ""
echo "=== Test: idempotency ==="
md5_before=$(md5sum "$TESTDIR/settings.json" | cut -d' ' -f1)
output2=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" 2>&1) || true
md5_after=$(md5sum "$TESTDIR/settings.json" | cut -d' ' -f1)

if [[ "$md5_before" == "$md5_after" ]]; then
    pass "idempotent (md5 unchanged)"
else
    fail "idempotent (md5 unchanged)" "md5 changed"
fi

# ===== Test: --skip-permissions =====
echo ""
echo "=== Test: --skip-permissions ==="
output3=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" --skip-permissions 2>&1) || true

if echo "$output3" | grep -q 'Skipped: permissions management'; then
    pass "--skip-permissions message"
else
    fail "--skip-permissions message" "expected skip message in output"
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
