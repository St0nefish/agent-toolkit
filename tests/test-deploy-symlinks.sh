#!/usr/bin/env bash
# Tests for deploy.sh symlink creation and layout
# Run from repo root: bash tests/test-deploy-symlinks.sh
#
# Uses a mini-repo with deploy.sh copied in to test symlink layouts:
# single .md, multiple .md, README.md exclusion, tool dirs, hook dirs,
# --on-path, --project, and --dry-run.

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

# Set up mini-repo
cp "$DEPLOY" "$MINI_REPO/deploy.sh"
chmod +x "$MINI_REPO/deploy.sh"
MINI_DEPLOY="$MINI_REPO/deploy.sh"

# Tool "single" — one .md file
mkdir -p "$MINI_REPO/tools/single/bin"
echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/single/bin/single-script"
chmod +x "$MINI_REPO/tools/single/bin/single-script"
cat > "$MINI_REPO/tools/single/single.md" << 'EOF'
---
description: Single skill tool
---
# Single
EOF

# Tool "multi" — two .md files
mkdir -p "$MINI_REPO/tools/multi/bin"
echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/multi/bin/multi-script"
chmod +x "$MINI_REPO/tools/multi/bin/multi-script"
cat > "$MINI_REPO/tools/multi/start.md" << 'EOF'
---
description: Multi start skill
---
# Start
EOF
cat > "$MINI_REPO/tools/multi/stop.md" << 'EOF'
---
description: Multi stop skill
---
# Stop
EOF

# Tool "with-readme" — one real .md + README.md
mkdir -p "$MINI_REPO/tools/with-readme/bin"
echo '#!/usr/bin/env bash' > "$MINI_REPO/tools/with-readme/bin/readme-script"
chmod +x "$MINI_REPO/tools/with-readme/bin/readme-script"
cat > "$MINI_REPO/tools/with-readme/with-readme.md" << 'EOF'
---
description: Tool with readme
---
# With Readme
EOF
cat > "$MINI_REPO/tools/with-readme/README.md" << 'EOF'
# Developer notes — should not be deployed as a skill
EOF

# Hook "test-hook"
mkdir -p "$MINI_REPO/hooks/test-hook"
cat > "$MINI_REPO/hooks/test-hook/hook.sh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MINI_REPO/hooks/test-hook/hook.sh"

# ===== Test: basic symlink layout =====
echo ""
echo "=== Test: basic symlink layout ==="
output=$(CLAUDE_CONFIG_DIR="$TESTDIR" "$MINI_DEPLOY" --skip-permissions 2>&1) || true

# Single .md → commands/<name>.md
if [[ -L "$TESTDIR/commands/single.md" ]]; then
    pass "single .md: symlink at commands/single.md"
else
    fail "single .md: symlink at commands/single.md" "not found"
fi

# Multi .md → commands/<tool-name>/ directory with symlinks inside
if [[ -d "$TESTDIR/commands/multi" ]]; then
    pass "multi .md: subdirectory commands/multi/ exists"
else
    fail "multi .md: subdirectory commands/multi/ exists" "not found"
fi

if [[ -L "$TESTDIR/commands/multi/start.md" ]]; then
    pass "multi .md: start.md symlink in subdirectory"
else
    fail "multi .md: start.md symlink in subdirectory" "not found"
fi

if [[ -L "$TESTDIR/commands/multi/stop.md" ]]; then
    pass "multi .md: stop.md symlink in subdirectory"
else
    fail "multi .md: stop.md symlink in subdirectory" "not found"
fi

# README.md excluded
if [[ -L "$TESTDIR/commands/README.md" ]] || [[ -L "$TESTDIR/commands/with-readme/README.md" ]]; then
    fail "README.md excluded from deployment" "README.md symlink found"
else
    pass "README.md excluded from deployment"
fi

# The real skill should still deploy
if [[ -L "$TESTDIR/commands/with-readme.md" ]]; then
    pass "with-readme.md skill deployed (README excluded)"
else
    fail "with-readme.md skill deployed (README excluded)" "not found"
fi

# Tool dirs symlinked to tools/
if [[ -L "$TESTDIR/tools/single" ]]; then
    pass "tool dir: tools/single symlinked"
else
    fail "tool dir: tools/single symlinked" "not found"
fi

if [[ -L "$TESTDIR/tools/multi" ]]; then
    pass "tool dir: tools/multi symlinked"
else
    fail "tool dir: tools/multi symlinked" "not found"
fi

# Hook dir symlinked to hooks/
if [[ -L "$TESTDIR/hooks/test-hook" ]]; then
    pass "hook dir: hooks/test-hook symlinked"
else
    fail "hook dir: hooks/test-hook symlinked" "not found"
fi

# ===== Test: --on-path =====
echo ""
echo "=== Test: --on-path symlinks scripts to ~/.local/bin/ ==="
TESTDIR_PATH=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR_PATH"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_PATH" HOME="$FAKE_HOME" "$MINI_DEPLOY" --on-path --skip-permissions 2>&1) || true

if [[ -L "$FAKE_HOME/.local/bin/single-script" ]]; then
    pass "--on-path: single-script in ~/.local/bin/"
else
    fail "--on-path: single-script in ~/.local/bin/" "symlink not found"
fi

if [[ -L "$FAKE_HOME/.local/bin/multi-script" ]]; then
    pass "--on-path: multi-script in ~/.local/bin/"
else
    fail "--on-path: multi-script in ~/.local/bin/" "symlink not found"
fi

# ===== Test: --project =====
echo ""
echo "=== Test: --project deploys skills to project path ==="
TESTDIR_PROJ=$(mktemp -d)
PROJECT_DIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR_PATH" "$TESTDIR_PROJ" "$PROJECT_DIR"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_PROJ" "$MINI_DEPLOY" --project "$PROJECT_DIR" --skip-permissions 2>&1) || true

# Skills should go to project
if [[ -L "$PROJECT_DIR/.claude/commands/single.md" ]]; then
    pass "--project: skill in project commands/"
else
    fail "--project: skill in project commands/" "not found"
fi

# Tool dirs should still go to global tools/
if [[ -L "$TESTDIR_PROJ/tools/single" ]]; then
    pass "--project: tool dir still in global tools/"
else
    fail "--project: tool dir still in global tools/" "not found"
fi

# Skills should NOT be in global commands
if [[ ! -L "$TESTDIR_PROJ/commands/single.md" ]]; then
    pass "--project: skill NOT in global commands/"
else
    fail "--project: skill NOT in global commands/" "found in global commands"
fi

# ===== Test: --dry-run =====
echo ""
echo "=== Test: --dry-run creates no symlinks ==="
TESTDIR_DRY=$(mktemp -d)
trap 'rm -rf "$TESTDIR" "$MINI_REPO" "$FAKE_HOME" "$TESTDIR_PATH" "$TESTDIR_PROJ" "$PROJECT_DIR" "$TESTDIR_DRY"' EXIT

output=$(CLAUDE_CONFIG_DIR="$TESTDIR_DRY" "$MINI_DEPLOY" --dry-run --skip-permissions 2>&1) || true

if [[ ! -L "$TESTDIR_DRY/tools/single" ]]; then
    pass "--dry-run: no tool symlinks created"
else
    fail "--dry-run: no tool symlinks created" "symlink found"
fi

if [[ ! -L "$TESTDIR_DRY/commands/single.md" ]]; then
    pass "--dry-run: no skill symlinks created"
else
    fail "--dry-run: no skill symlinks created" "symlink found"
fi

if echo "$output" | grep -q '^> '; then
    pass "--dry-run: output has > prefixed lines"
else
    fail "--dry-run: output has > prefixed lines" "no > lines found"
fi

if echo "$output" | grep -q 'DRY RUN'; then
    pass "--dry-run: output has DRY RUN banner"
else
    fail "--dry-run: output has DRY RUN banner" "no DRY RUN banner"
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
