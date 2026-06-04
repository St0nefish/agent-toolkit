#!/usr/bin/env bash
# test-installer.sh — Validate user-level install/update flow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-copilot-git-worktree.sh"
SCRATCH_ROOT="$REPO_ROOT/.scratch-tests/git-worktree/test-installer-$$"
COPILOT_HOME="$SCRATCH_ROOT/copilot-home"
TARGET_DIR="$COPILOT_HOME/extensions/git-worktree"
SOURCE_EXT="$REPO_ROOT/.github/extensions/git-worktree"

PASS=0
FAIL=0

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s\n" "$1"
  ((FAIL++)) || true
}

rm -rf "$SCRATCH_ROOT"
mkdir -p "$SCRATCH_ROOT"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

echo "── install ──"
COPILOT_HOME="$COPILOT_HOME" AGENT_TOOLKIT_SOURCE_DIR="$REPO_ROOT" bash "$INSTALLER" >/dev/null 2>&1
if [[ -f "$TARGET_DIR/extension.mjs" ]]; then
  pass "installer writes extension into ~/.copilot/extensions"
else
  fail "installer did not create extension.mjs"
fi

if cmp -s "$SOURCE_EXT/extension.mjs" "$TARGET_DIR/extension.mjs"; then
  pass "installed extension matches source"
else
  fail "installed extension differs from source"
fi

echo "── update is idempotent ──"
echo "mutated" >>"$TARGET_DIR/README.md"
COPILOT_HOME="$COPILOT_HOME" AGENT_TOOLKIT_SOURCE_DIR="$REPO_ROOT" bash "$INSTALLER" >/dev/null 2>&1
if cmp -s "$SOURCE_EXT/README.md" "$TARGET_DIR/README.md"; then
  pass "rerun restores canonical files"
else
  fail "rerun did not restore canonical README"
fi

if [[ -x "$TARGET_DIR/scripts/worktree-create.sh" ]]; then
  pass "shell scripts stay executable"
else
  fail "shell scripts are not executable after install"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
