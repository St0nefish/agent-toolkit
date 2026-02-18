#!/usr/bin/env bash
# Tests for deploy.sh CLI argument validation
# Run from repo root: bash tests/test-deploy-cli-validation.sh
#
# Uses a mini-repo with deploy.sh copied in to avoid noise from real tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$REPO_DIR/deploy.sh"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Create isolated temp dir with a mini-repo
TESTDIR=$(mktemp -d)
MINI_REPO=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO"' EXIT
export CLAUDE_CONFIG_DIR="$TESTDIR"
echo "Using TESTDIR=$TESTDIR MINI_REPO=$MINI_REPO"

# Set up mini-repo: copy deploy.sh and create a minimal tool
cp "$DEPLOY" "$MINI_REPO/deploy.sh"
chmod +x "$MINI_REPO/deploy.sh"
mkdir -p "$MINI_REPO/tools/alpha/bin"
echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/alpha/bin/alpha"
chmod +x "$MINI_REPO/tools/alpha/bin/alpha"
cat > "$MINI_REPO/tools/alpha/alpha.md" << 'EOF'
---
description: Test tool alpha
---
# Alpha
EOF

MINI_DEPLOY="$MINI_REPO/deploy.sh"

# ===== Test: --include + --exclude → error + exit 1 =====
echo ""
echo "=== Test: --include + --exclude are mutually exclusive ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$MINI_DEPLOY" --include alpha --exclude alpha 2>&1) && rc=$? || rc=$?

if [[ "$rc" -eq 1 ]]; then
    pass "--include + --exclude exits 1"
else
    fail "--include + --exclude exits 1" "exit code was $rc"
fi

if echo "$output" | grep -qi 'mutually exclusive'; then
    pass "--include + --exclude error message"
else
    fail "--include + --exclude error message" "expected 'mutually exclusive' in output"
fi

# ===== Test: --project + --on-path → error + exit 1 =====
echo ""
echo "=== Test: --project + --on-path are incompatible ==="
project_dir=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$project_dir"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$MINI_DEPLOY" --project "$project_dir" --on-path 2>&1) && rc=$? || rc=$?

if [[ "$rc" -eq 1 ]]; then
    pass "--project + --on-path exits 1"
else
    fail "--project + --on-path exits 1" "exit code was $rc"
fi

if echo "$output" | grep -qi 'not supported'; then
    pass "--project + --on-path error message"
else
    fail "--project + --on-path error message" "expected 'not supported' in output"
fi

# ===== Test: --project /nonexistent → error + exit 1 =====
echo ""
echo "=== Test: --project with nonexistent path ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$MINI_DEPLOY" --project /nonexistent/path/that/does/not/exist 2>&1) && rc=$? || rc=$?

if [[ "$rc" -eq 1 ]]; then
    pass "--project nonexistent exits 1"
else
    fail "--project nonexistent exits 1" "exit code was $rc"
fi

if echo "$output" | grep -qi 'does not exist'; then
    pass "--project nonexistent error message"
else
    fail "--project nonexistent error message" "expected 'does not exist' in output"
fi

# ===== Test: unknown flag → error + exit 1 =====
echo ""
echo "=== Test: unknown flag ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$MINI_DEPLOY" --bogus-flag 2>&1) && rc=$? || rc=$?

if [[ "$rc" -eq 1 ]]; then
    pass "unknown flag exits 1"
else
    fail "unknown flag exits 1" "exit code was $rc"
fi

if echo "$output" | grep -qi 'unknown option'; then
    pass "unknown flag error message"
else
    fail "unknown flag error message" "expected 'Unknown option' in output"
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
