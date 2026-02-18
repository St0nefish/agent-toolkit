#!/usr/bin/env bash
# Tests for deploy.sh --include, --exclude, condition.sh, and enabled config
# Run from repo root: bash tests/test-deploy-filtering.sh
#
# Uses a mini-repo with deploy.sh copied in and 3 synthetic tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$REPO_DIR/deploy.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Create isolated temp dirs
TESTDIR=$(mktemp -d)
MINI_REPO=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO"' EXIT
echo "Using TESTDIR=$TESTDIR MINI_REPO=$MINI_REPO"

# Set up mini-repo with deploy.sh and 3 tools: alpha, beta, gamma
cp "$DEPLOY" "$MINI_REPO/deploy.sh"
chmod +x "$MINI_REPO/deploy.sh"
MINI_DEPLOY="$MINI_REPO/deploy.sh"

for name in alpha beta gamma; do
    mkdir -p "$MINI_REPO/tools/$name/bin"
    echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/$name/bin/$name"
    chmod +x "$MINI_REPO/tools/$name/bin/$name"
    cat > "$MINI_REPO/tools/$name/$name.md" << EOF
---
description: Test tool $name
---
# $name
EOF
done

# ===== Test: --include alpha → only alpha deployed =====
echo ""
echo "=== Test: --include deploys only specified tool ==="
TESTDIR_INC=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_INC" "$MINI_DEPLOY" --include alpha --skip-permissions 2>&1) || true

if [[ -L "$TESTDIR_INC/tools/alpha" ]]; then
    pass "--include alpha: alpha deployed"
else
    fail "--include alpha: alpha deployed" "alpha symlink not found"
fi

if [[ ! -L "$TESTDIR_INC/tools/beta" ]]; then
    pass "--include alpha: beta not deployed"
else
    fail "--include alpha: beta not deployed" "beta symlink found"
fi

if [[ ! -L "$TESTDIR_INC/tools/gamma" ]]; then
    pass "--include alpha: gamma not deployed"
else
    fail "--include alpha: gamma not deployed" "gamma symlink found"
fi

if echo "$output" | grep -q 'Skipped: beta (filtered out)'; then
    pass "--include alpha: beta filtered out message"
else
    fail "--include alpha: beta filtered out message" "no matching line"
fi

if echo "$output" | grep -q 'Skipped: gamma (filtered out)'; then
    pass "--include alpha: gamma filtered out message"
else
    fail "--include alpha: gamma filtered out message" "no matching line"
fi

# ===== Test: --exclude beta → alpha+gamma deployed =====
echo ""
echo "=== Test: --exclude skips specified tool ==="
TESTDIR_EXC=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_EXC" "$MINI_DEPLOY" --exclude beta --skip-permissions 2>&1) || true

if [[ -L "$TESTDIR_EXC/tools/alpha" ]]; then
    pass "--exclude beta: alpha deployed"
else
    fail "--exclude beta: alpha deployed" "alpha symlink not found"
fi

if [[ ! -L "$TESTDIR_EXC/tools/beta" ]]; then
    pass "--exclude beta: beta not deployed"
else
    fail "--exclude beta: beta not deployed" "beta symlink found"
fi

if [[ -L "$TESTDIR_EXC/tools/gamma" ]]; then
    pass "--exclude beta: gamma deployed"
else
    fail "--exclude beta: gamma deployed" "gamma symlink not found"
fi

if echo "$output" | grep -q 'Skipped: beta (filtered out)'; then
    pass "--exclude beta: beta filtered out message"
else
    fail "--exclude beta: beta filtered out message" "no matching line"
fi

# ===== Test: condition.sh exits non-zero → tool skipped =====
echo ""
echo "=== Test: condition.sh gates deployment ==="
# Add a failing condition.sh to beta
cat > "$MINI_REPO/tools/beta/condition.sh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MINI_REPO/tools/beta/condition.sh"

TESTDIR_COND=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC" "$TESTDIR_COND"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_COND" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ ! -L "$TESTDIR_COND/tools/beta" ]]; then
    pass "condition.sh exit 1: beta not deployed"
else
    fail "condition.sh exit 1: beta not deployed" "beta symlink found"
fi

if echo "$output" | grep -q 'Skipped: beta (condition not met)'; then
    pass "condition.sh exit 1: condition not met message"
else
    fail "condition.sh exit 1: condition not met message" "no matching line"
fi

if [[ -L "$TESTDIR_COND/tools/alpha" ]]; then
    pass "condition.sh: alpha still deployed"
else
    fail "condition.sh: alpha still deployed" "alpha symlink not found"
fi

# Switch beta condition to passing
cat > "$MINI_REPO/tools/beta/condition.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF

TESTDIR_COND2=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC" "$TESTDIR_COND" "$TESTDIR_COND2"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_COND2" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ -L "$TESTDIR_COND2/tools/beta" ]]; then
    pass "condition.sh exit 0: beta deployed"
else
    fail "condition.sh exit 0: beta deployed" "beta symlink not found"
fi

# Clean up condition.sh for subsequent tests
rm "$MINI_REPO/tools/beta/condition.sh"

# ===== Test: enabled: false in deploy.json → tool skipped =====
echo ""
echo "=== Test: enabled: false disables tool ==="
cat > "$MINI_REPO/tools/gamma/deploy.json" << 'EOF'
{ "enabled": false }
EOF

TESTDIR_DIS=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC" "$TESTDIR_COND" "$TESTDIR_COND2" "$TESTDIR_DIS"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_DIS" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ ! -L "$TESTDIR_DIS/tools/gamma" ]]; then
    pass "enabled: false: gamma not deployed"
else
    fail "enabled: false: gamma not deployed" "gamma symlink found"
fi

if echo "$output" | grep -q 'Skipped: gamma (disabled by config)'; then
    pass "enabled: false: disabled by config message"
else
    fail "enabled: false: disabled by config message" "no matching line"
fi

if [[ -L "$TESTDIR_DIS/tools/alpha" ]]; then
    pass "enabled: false: alpha still deployed"
else
    fail "enabled: false: alpha still deployed" "alpha symlink not found"
fi

# Clean up
rm "$MINI_REPO/tools/gamma/deploy.json"

# ===== Test: filtering applies to hooks too =====
echo ""
echo "=== Test: --exclude filters hooks ==="
mkdir -p "$MINI_REPO/hooks/test-hook"
cat > "$MINI_REPO/hooks/test-hook/hook.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MINI_REPO/hooks/test-hook/hook.sh"

TESTDIR_HOOK=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC" "$TESTDIR_COND" "$TESTDIR_COND2" "$TESTDIR_DIS" "$TESTDIR_HOOK"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_HOOK" "$MINI_DEPLOY" --exclude test-hook --skip-permissions 2>&1) || true

if echo "$output" | grep -q 'Skipped: hook test-hook (filtered out)'; then
    pass "--exclude filters hooks"
else
    fail "--exclude filters hooks" "no matching line"
fi

if [[ ! -L "$TESTDIR_HOOK/hooks/test-hook" ]]; then
    pass "--exclude: hook not symlinked"
else
    fail "--exclude: hook not symlinked" "hook symlink found"
fi

# Deploy without exclude — hook should appear
TESTDIR_HOOK2=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$TESTDIR_INC" "$TESTDIR_EXC" "$TESTDIR_COND" "$TESTDIR_COND2" "$TESTDIR_DIS" "$TESTDIR_HOOK" "$TESTDIR_HOOK2"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_HOOK2" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ -L "$TESTDIR_HOOK2/hooks/test-hook" ]]; then
    pass "hook deployed without --exclude"
else
    fail "hook deployed without --exclude" "hook symlink not found"
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
