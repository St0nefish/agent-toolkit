#!/usr/bin/env bash
# Tests for deploy.sh config layer merging (resolve_config behavior)
# Run from repo root: bash tests/test-deploy-config-merge.sh
#
# Uses a mini-repo with deploy.sh to test config precedence:
# repo-root deploy.json < repo-root deploy.local.json < tool deploy.json < tool deploy.local.json < CLI flags

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
FAKE_HOME=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME"' EXIT
echo "Using TESTDIR=$TESTDIR MINI_REPO=$MINI_REPO"

# Set up mini-repo base
cp "$DEPLOY" "$MINI_REPO/deploy.sh"
chmod +x "$MINI_REPO/deploy.sh"
MINI_DEPLOY="$MINI_REPO/deploy.sh"

# Create a tool "configtest"
setup_tool() {
    rm -rf "$MINI_REPO/skills"
    mkdir -p "$MINI_REPO/skills/configtest/bin"
    echo '#!/usr/bin/env bash' > "$MINI_REPO/skills/configtest/bin/configtest"
    chmod +x "$MINI_REPO/skills/configtest/bin/configtest"
    cat > "$MINI_REPO/skills/configtest/configtest.md" << 'EOF'
---
description: Config test tool
---
# Config Test
EOF
    # Clean any leftover configs
    rm -f "$MINI_REPO/deploy.json" "$MINI_REPO/deploy.local.json"
    rm -f "$MINI_REPO/skills/configtest/deploy.json" "$MINI_REPO/skills/configtest/deploy.local.json"
}

# ===== Test: tool deploy.json overrides repo-root deploy.json =====
echo ""
echo "=== Test: tool deploy.json overrides repo-root deploy.json ==="
setup_tool

# Repo-root says on_path: false
cat > "$MINI_REPO/deploy.json" << 'EOF'
{ "on_path": false }
EOF

# Tool-level says on_path: true
cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{ "on_path": true }
EOF

TESTDIR1=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR1" HOME="$FAKE_HOME" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ -L "$FAKE_HOME/.local/bin/configtest" ]]; then
    pass "tool deploy.json on_path overrides repo-root"
else
    fail "tool deploy.json on_path overrides repo-root" "script not in ~/.local/bin/"
fi

# ===== Test: tool deploy.local.json overrides tool deploy.json =====
echo ""
echo "=== Test: tool deploy.local.json overrides tool deploy.json ==="
setup_tool

# Tool deploy.json says enabled: true
cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{ "enabled": true }
EOF

# Tool deploy.local.json says enabled: false
cat > "$MINI_REPO/skills/configtest/deploy.local.json" << 'EOF'
{ "enabled": false }
EOF

TESTDIR2=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR2" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if echo "$output" | grep -q 'Skipped: configtest (disabled by config)'; then
    pass "tool deploy.local.json overrides deploy.json (disabled)"
else
    fail "tool deploy.local.json overrides deploy.json (disabled)" "tool was not skipped"
fi

# ===== Test: on_path: true in config deploys to ~/.local/bin/ without CLI flag =====
echo ""
echo "=== Test: on_path in config works without --on-path flag ==="
setup_tool

cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{ "on_path": true }
EOF

# Clean fake home
rm -rf "$FAKE_HOME/.local"

TESTDIR3=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2" "$TESTDIR3"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR3" HOME="$FAKE_HOME" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ -L "$FAKE_HOME/.local/bin/configtest" ]]; then
    pass "on_path: true in config deploys to PATH"
else
    fail "on_path: true in config deploys to PATH" "script not in ~/.local/bin/"
fi

# ===== Test: scope: project skips tool when no --project flag =====
echo ""
echo "=== Test: scope: project skips without --project ==="
setup_tool

cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{ "scope": "project" }
EOF

TESTDIR4=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2" "$TESTDIR3" "$TESTDIR4"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR4" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if echo "$output" | grep -q 'Skipped: configtest (scope=project, no --project flag given)'; then
    pass "scope: project skips without --project"
else
    fail "scope: project skips without --project" "tool was not skipped"
fi

if [[ ! -L "$TESTDIR4/commands/configtest.md" ]]; then
    pass "scope: project: no skill symlink created"
else
    fail "scope: project: no skill symlink created" "skill symlink found"
fi

# ===== Test: CLI --on-path overrides config on_path: false =====
echo ""
echo "=== Test: CLI --on-path overrides config on_path: false ==="
setup_tool

cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{ "on_path": false }
EOF

# Clean fake home
rm -rf "$FAKE_HOME/.local"

TESTDIR5=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2" "$TESTDIR3" "$TESTDIR4" "$TESTDIR5"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR5" HOME="$FAKE_HOME" "$MINI_DEPLOY" --on-path --skip-permissions 2>&1) || true

if [[ -L "$FAKE_HOME/.local/bin/configtest" ]]; then
    pass "CLI --on-path overrides config on_path: false"
else
    fail "CLI --on-path overrides config on_path: false" "script not in ~/.local/bin/"
fi

# ===== Test: permissions.deny entries collected and written =====
echo ""
echo "=== Test: permissions.deny entries collected ==="
setup_tool

cat > "$MINI_REPO/skills/configtest/deploy.json" << 'EOF'
{
  "permissions": {
    "allow": ["Bash(configtest)"],
    "deny": ["Bash(rm -rf *)"]
  }
}
EOF

TESTDIR6=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2" "$TESTDIR3" "$TESTDIR4" "$TESTDIR5" "$TESTDIR6"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR6" "$MINI_DEPLOY" 2>&1) || true

if jq -e '.permissions.deny | index("Bash(rm -rf *)")' "$TESTDIR6/settings.json" >/dev/null 2>&1; then
    pass "permissions.deny entry written"
else
    fail "permissions.deny entry written" "not found in settings.json"
fi

if jq -e '.permissions.allow | index("Bash(configtest)")' "$TESTDIR6/settings.json" >/dev/null 2>&1; then
    pass "permissions.allow entry written alongside deny"
else
    fail "permissions.allow entry written alongside deny" "not found in settings.json"
fi

# ===== Test: repo-root deploy.local.json overrides repo-root deploy.json =====
echo ""
echo "=== Test: repo-root deploy.local.json overrides repo-root deploy.json ==="
setup_tool

# Repo-root deploy.json says on_path: true
cat > "$MINI_REPO/deploy.json" << 'EOF'
{ "on_path": true }
EOF

# Repo-root deploy.local.json says on_path: false
cat > "$MINI_REPO/deploy.local.json" << 'EOF'
{ "on_path": false }
EOF

# Clean fake home
rm -rf "$FAKE_HOME/.local"

TESTDIR7=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR1" "$TESTDIR2" "$TESTDIR3" "$TESTDIR4" "$TESTDIR5" "$TESTDIR6" "$TESTDIR7"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR7" HOME="$FAKE_HOME" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

if [[ ! -L "$FAKE_HOME/.local/bin/configtest" ]]; then
    pass "repo-root deploy.local.json overrides deploy.json (on_path: false wins)"
else
    fail "repo-root deploy.local.json overrides deploy.json (on_path: false wins)" "script found in ~/.local/bin/"
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
