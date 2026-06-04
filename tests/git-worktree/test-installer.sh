#!/usr/bin/env bash
# test-installer.sh — Validate user-level install/update flow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-copilot-git-worktree.sh"
SCRATCH_ROOT="$REPO_ROOT/.scratch-tests/git-worktree/test-installer-$$"
COPILOT_HOME="$SCRATCH_ROOT/copilot-home"
TARGET_DIR="$COPILOT_HOME/extensions/git-worktree"
SOURCE_EXT="$REPO_ROOT/copilot-extensions/git-worktree"
PERMISSIONS_FILE="$COPILOT_HOME/permissions-config.json"
LOCATION_KEY="$SCRATCH_ROOT/project"
BIN_DIR="$SCRATCH_ROOT/bin"
HELPER_BIN="$BIN_DIR/copilot-git-worktree-allow"
SECOND_REPO="$SCRATCH_ROOT/another-project"

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
mkdir -p "$LOCATION_KEY"
mkdir -p "$SECOND_REPO"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

echo "── install ──"
COPILOT_HOME="$COPILOT_HOME" COPILOT_BIN_DIR="$BIN_DIR" AGENT_TOOLKIT_SOURCE_DIR="$REPO_ROOT" AGENT_TOOLKIT_PERMISSION_LOCATION="$LOCATION_KEY" bash "$INSTALLER" >/dev/null 2>&1
if [[ -f "$TARGET_DIR/extension.mjs" ]]; then
  pass "installer writes extension into ~/.copilot/extensions"
else
  fail "installer did not create extension.mjs"
fi

if [[ -x "$HELPER_BIN" ]]; then
  pass "installer installs global helper command"
else
  fail "installer did not install helper command"
fi

if cmp -s "$SOURCE_EXT/extension.mjs" "$TARGET_DIR/extension.mjs"; then
  pass "installed extension matches source"
else
  fail "installed extension differs from source"
fi

if jq -e --arg loc "$LOCATION_KEY" '
  (.locations[$loc].tool_approvals // []) |
  any(.kind == "extension-permission-access" and .extensionName == "user:git-worktree")
' "$PERMISSIONS_FILE" >/dev/null 2>&1; then
  pass "installer seeds extension permission approval"
else
  fail "installer did not seed extension permission approval"
fi

if jq -e --arg loc "$LOCATION_KEY" '
  [.locations[$loc].tool_approvals[]? | select(.kind == "custom-tool") | .toolName] |
  index("sf_git_worktree_status") != null and
  index("sf_git_worktree_create") != null and
  index("sf_git_worktree_remove") != null and
  index("sf_git_worktree_suggest") != null
' "$PERMISSIONS_FILE" >/dev/null 2>&1; then
  pass "installer seeds custom tool approvals"
else
  fail "installer did not seed custom tool approvals"
fi

echo "── update is idempotent ──"
echo "mutated" >>"$TARGET_DIR/README.md"
COPILOT_HOME="$COPILOT_HOME" COPILOT_BIN_DIR="$BIN_DIR" AGENT_TOOLKIT_SOURCE_DIR="$REPO_ROOT" AGENT_TOOLKIT_PERMISSION_LOCATION="$LOCATION_KEY" bash "$INSTALLER" >/dev/null 2>&1
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

COUNT=$(jq -r --arg loc "$LOCATION_KEY" '
  [.locations[$loc].tool_approvals[]? |
    select(
      (.kind == "extension-permission-access" and .extensionName == "user:git-worktree") or
      (.kind == "custom-tool" and (.toolName | startswith("sf_git_worktree_")))
    )
  ] | length
' "$PERMISSIONS_FILE")
if [[ "$COUNT" == "5" ]]; then
  pass "rerun keeps permission entries deduplicated"
else
  fail "rerun duplicated permission entries"
fi

echo "── helper seeds arbitrary repo without source tree ──"
COPILOT_HOME="$COPILOT_HOME" "$HELPER_BIN" "$SECOND_REPO" >/dev/null 2>&1
if jq -e --arg loc "$SECOND_REPO" '
  (.locations[$loc].tool_approvals // []) |
  any(.kind == "extension-permission-access" and .extensionName == "user:git-worktree")
' "$PERMISSIONS_FILE" >/dev/null 2>&1; then
  pass "helper seeds arbitrary repo root"
else
  fail "helper did not seed arbitrary repo root"
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
