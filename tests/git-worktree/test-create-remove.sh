#!/usr/bin/env bash
# test-create-remove.sh — Integration tests for worktree-create.sh and worktree-remove.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/../../plugins-copilot/git-worktree/scripts/worktree-create.sh"
REMOVE_SCRIPT="$SCRIPT_DIR/../../plugins-copilot/git-worktree/scripts/worktree-remove.sh"
LIST_SCRIPT="$SCRIPT_DIR/../../plugins-copilot/git-worktree/scripts/worktree-list.sh"

PASS=0
FAIL=0

assert_ok() {
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (command failed)\n" "$label"
    ((FAIL++)) || true
  fi
}

assert_fail() {
  local label="$1"
  shift
  if ! "$@" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (expected failure, got success)\n" "$label"
    ((FAIL++)) || true
  fi
}

assert_dir_exists() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (directory not found: %s)\n" "$label" "$path"
    ((FAIL++)) || true
  fi
}

assert_dir_gone() {
  local label="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (directory still exists: %s)\n" "$label" "$path"
    ((FAIL++)) || true
  fi
}

# ── Setup: temp git repo ──────────────────────────────────────────────────────

# Resolve to canonical path — macOS mktemp returns /var/folders/... but git
# reports /private/var/folders/... (via the /var → /private/var symlink).
TMPDIR_BASE=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

MAIN_REPO="$TMPDIR_BASE/my-project"
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" config user.email "test@test.com"
git -C "$MAIN_REPO" config user.name "Test"
echo "init" >"$MAIN_REPO/README.md"
git -C "$MAIN_REPO" add .
git -C "$MAIN_REPO" commit -q -m "init"

cd "$MAIN_REPO"
export WORKTREE_BASE_DIR="$TMPDIR_BASE/my-project-worktrees"

# ── Test: worktree-create.sh ─────────────────────────────────────────────────

echo "── worktree-create.sh ──"

WT_PATH="$WORKTREE_BASE_DIR/feature-auth"

assert_ok "create new worktree" \
  bash "$CREATE_SCRIPT" "feature/auth"

assert_dir_exists "worktree directory created" "$WT_PATH"

assert_ok "branch exists in worktree" \
  git -C "$WT_PATH" rev-parse --verify "refs/heads/feature/auth"

assert_fail "create duplicate fails" \
  bash "$CREATE_SCRIPT" "feature/auth"

# ── Test: worktree-list.sh ────────────────────────────────────────────────────

echo "── worktree-list.sh ──"

OUTPUT=$(bash "$LIST_SCRIPT" 2>/dev/null)

if echo "$OUTPUT" | grep -q "feature/auth"; then
  printf "  \033[32m✓\033[0m list shows created worktree\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m list does not show created worktree\n"
  ((FAIL++)) || true
fi

# ── Test: worktree-remove.sh ─────────────────────────────────────────────────

echo "── worktree-remove.sh ──"

assert_ok "remove by slug" \
  bash "$REMOVE_SCRIPT" "feature-auth"

assert_dir_gone "worktree directory removed" "$WT_PATH"

assert_fail "remove non-existent worktree fails" \
  bash "$REMOVE_SCRIPT" "nonexistent"

# ── Test: create then remove with --delete-branch ────────────────────────────

echo "── create → remove --delete-branch ──"

bash "$CREATE_SCRIPT" "cleanup-test" >/dev/null 2>&1
WT2_PATH="$WORKTREE_BASE_DIR/cleanup-test"

assert_dir_exists "second worktree created" "$WT2_PATH"

assert_ok "remove with --delete-branch" \
  bash "$REMOVE_SCRIPT" "cleanup-test" --delete-branch

assert_dir_gone "second worktree removed" "$WT2_PATH"

if ! git rev-parse --verify "refs/heads/cleanup-test" >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m branch deleted after --delete-branch\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m branch still exists after --delete-branch\n"
  ((FAIL++)) || true
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
