#!/usr/bin/env bash
# test-lib.sh — Tests for worktree-lib.sh shared functions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../plugins-copilot/git-worktree/scripts/worktree-lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n    expected: %s\n    got:      %s\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (returned non-zero)\n" "$label"
    ((FAIL++)) || true
  fi
}

assert_false() {
  local label="$1"
  shift
  if ! "$@" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (returned zero, expected failure)\n" "$label"
    ((FAIL++)) || true
  fi
}

# ── Setup: temp git repo ──────────────────────────────────────────────────────

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

MAIN_REPO="$TMPDIR_BASE/my-project"
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" config user.email "test@test.com"
git -C "$MAIN_REPO" config user.name "Test"
echo "init" > "$MAIN_REPO/README.md"
git -C "$MAIN_REPO" add .
git -C "$MAIN_REPO" commit -q -m "init"

cd "$MAIN_REPO"
# shellcheck source=../../plugins-copilot/git-worktree/scripts/worktree-lib.sh
source "$LIB"

# ── Tests: slug_from_branch ───────────────────────────────────────────────────

echo "── slug_from_branch ──"

assert_eq "simple name unchanged" "feature-auth" "$(slug_from_branch "feature-auth")"
assert_eq "slash replaced" "feature-auth-jwt" "$(slug_from_branch "feature/auth-jwt")"
assert_eq "special chars replaced" "my-branch-123" "$(slug_from_branch "my-branch-123")"
assert_eq "consecutive dashes collapsed" "feature-auth" "$(slug_from_branch "feature//auth")"
assert_eq "leading dashes removed" "branch" "$(slug_from_branch "--branch")"

# ── Tests: git_root ───────────────────────────────────────────────────────────

echo "── git_root ──"

assert_eq "git_root returns repo path" "$MAIN_REPO" "$(git_root)"

# ── Tests: repo_name ──────────────────────────────────────────────────────────

echo "── repo_name ──"

assert_eq "repo_name returns dirname" "my-project" "$(repo_name)"

# ── Tests: worktree_base_dir ──────────────────────────────────────────────────

echo "── worktree_base_dir ──"

assert_eq "default base dir is sibling" "$TMPDIR_BASE/my-project-worktrees" "$(worktree_base_dir)"
assert_eq "WORKTREE_BASE_DIR override" "/custom/path" "$(WORKTREE_BASE_DIR=/custom/path worktree_base_dir)"

# ── Tests: list_worktrees and is_worktree_path ────────────────────────────────

echo "── list_worktrees / is_worktree_path ──"

WT_PATH="$TMPDIR_BASE/my-project-worktrees/test-branch"
mkdir -p "$(dirname "$WT_PATH")"
git worktree add -b test-branch "$WT_PATH" >/dev/null 2>&1

COUNT=$(list_worktrees | wc -l | tr -d ' ')
assert_eq "list_worktrees returns 1 entry" "1" "$COUNT"

assert_true "is_worktree_path: exact match" is_worktree_path "$WT_PATH"
assert_true "is_worktree_path: subpath" is_worktree_path "$WT_PATH/src/file.txt"
assert_false "is_worktree_path: unrelated path" is_worktree_path "/tmp/other"
assert_false "is_worktree_path: empty string" is_worktree_path ""

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
