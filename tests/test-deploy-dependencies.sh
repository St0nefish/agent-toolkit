#!/usr/bin/env bash
# Tests for deploy.sh dependency support
# Run from repo root: bash tests/test-deploy-dependencies.sh
#
# Uses CLAUDE_CONFIG_DIR pointed at a temp directory — never touches real config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$REPO_DIR/deploy.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Portable md5 helper
file_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | cut -d' ' -f1
    else
        md5 -q "$1"
    fi
}

# Create isolated temp dir
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
export CLAUDE_CONFIG_DIR="$TESTDIR"
echo "Using TESTDIR=$TESTDIR"

# ===== Test: catchup depends on session — session tool dir is symlinked =====
echo ""
echo "=== Test: dependency tool dir is symlinked ==="
# Deploy only catchup — its dep (session) should get linked even though
# session is not in --include
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" --include catchup 2>&1) || true

if [[ -L "$TESTDIR/tools/session" ]]; then
    pass "session tool dir symlinked as dependency of catchup"
else
    fail "session tool dir symlinked as dependency of catchup" "symlink not found at $TESTDIR/tools/session"
fi

# Verify catchup tool itself is symlinked
if [[ -L "$TESTDIR/tools/catchup" ]]; then
    pass "catchup tool dir symlinked"
else
    fail "catchup tool dir symlinked" "symlink not found"
fi

echo ""
echo "=== Test: dependency permissions collected ==="
# Session's deploy.json permissions should be collected as a dependency
if jq -e '.permissions.allow | index("Bash(~/.claude/tools/session/bin/catchup)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "session catchup permission collected via dependency"
else
    fail "session catchup permission collected via dependency" "not found in settings.json"
fi

if jq -e '.permissions.allow | index("Bash(~/.claude/tools/session/bin/catchup *)")' "$TESTDIR/settings.json" >/dev/null 2>&1; then
    pass "session catchup wildcard permission collected"
else
    fail "session catchup wildcard permission collected" "not found in settings.json"
fi

echo ""
echo "=== Test: dependency skills NOT deployed ==="
# Session skills should NOT be in commands/ (session was only a dependency, not directly deployed)
if [[ -d "$TESTDIR/commands/session" ]]; then
    fail "session skills not deployed as dependency" "session/ directory found in commands/"
elif [[ -L "$TESTDIR/commands/start.md" ]] || [[ -L "$TESTDIR/commands/end.md" ]]; then
    fail "session skills not deployed as dependency" "session .md files found in commands/"
else
    pass "session skills not deployed as dependency"
fi

# Catchup's own skill SHOULD be deployed
if [[ -L "$TESTDIR/commands/catchup.md" ]]; then
    pass "catchup skill deployed"
else
    fail "catchup skill deployed" "catchup.md not found in commands/"
fi

echo ""
echo "=== Test: output mentions dependency linking ==="
if echo "$output" | grep -q 'dependency of catchup'; then
    pass "output mentions dependency linking"
else
    fail "output mentions dependency linking" "no matching line in output"
fi

echo ""
echo "=== Test: deploying session directly works standalone ==="
TESTDIR2=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$TESTDIR2"' EXIT

output2=$(CLAUDE_CONFIG_DIR="$TESTDIR2" "$DEPLOY" --include session 2>&1) || true

if [[ -L "$TESTDIR2/tools/session" ]]; then
    pass "session tool dir symlinked (direct deploy)"
else
    fail "session tool dir symlinked (direct deploy)" "symlink not found"
fi

# Session has no dependencies now, so no extra tools should be linked
if [[ -d "$TESTDIR2/commands/session" ]]; then
    pass "session skills directory exists"
else
    fail "session skills directory exists" "not found"
fi

echo ""
echo "=== Test: missing dependency warns but doesn't fail ==="
# Create a standalone mini repo structure to test missing deps
MINI_REPO=$(mktemp -d)
TESTDIR3=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$TESTDIR2" "$TESTDIR3" "$MINI_REPO"' EXIT

mkdir -p "$MINI_REPO/tools/test-tool/bin"
echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/test-tool/bin/test-script"
chmod +x "$MINI_REPO/tools/test-tool/bin/test-script"
cat > "$MINI_REPO/tools/test-tool/test-tool.md" << 'EOF'
---
description: Test tool with missing dep
---
# Test Tool
EOF
cat > "$MINI_REPO/tools/test-tool/deploy.json" << 'EOF'
{
  "dependencies": ["nonexistent-tool"]
}
EOF

cp "$DEPLOY" "$MINI_REPO/deploy.sh"
chmod +x "$MINI_REPO/deploy.sh"

output_missing=$(CLAUDE_CONFIG_DIR="$TESTDIR3" "$MINI_REPO/deploy.sh" 2>&1) || true

if echo "$output_missing" | grep -q "Warning: dependency 'nonexistent-tool' not found"; then
    pass "missing dependency warns"
else
    fail "missing dependency warns" "no warning in output"
fi

if echo "$output_missing" | grep -q "Deployed: test-tool"; then
    pass "deploy continues after missing dependency"
else
    fail "deploy continues after missing dependency" "tool was not deployed"
fi

echo ""
echo "=== Test: idempotent ==="
md5_before=$(file_md5 "$TESTDIR/settings.json")

output3=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$DEPLOY" --include catchup 2>&1) || true

md5_after=$(file_md5 "$TESTDIR/settings.json")

if [[ "$md5_before" == "$md5_after" ]]; then
    pass "idempotent (settings.json unchanged on re-deploy)"
else
    fail "idempotent (settings.json unchanged on re-deploy)" "md5 changed"
fi

if [[ -L "$TESTDIR/tools/session" ]]; then
    pass "session symlink survives re-deploy"
else
    fail "session symlink survives re-deploy" "symlink missing"
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
