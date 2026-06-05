#!/usr/bin/env bash
# test-lib.sh — Tests for worktree-lib.sh shared functions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/copilot-extensions/git-worktree/scripts/worktree-lib.sh"
SCRATCH_ROOT="$REPO_ROOT/.scratch-tests/git-worktree/test-lib-$$"

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

rm -rf "$SCRATCH_ROOT"
mkdir -p "$SCRATCH_ROOT"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT

MAIN_REPO="$SCRATCH_ROOT/my-project"
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" config user.email "test@test.com"
git -C "$MAIN_REPO" config user.name "Test"
echo "init" >"$MAIN_REPO/README.md"
git -C "$MAIN_REPO" add .
git -C "$MAIN_REPO" commit -q -m "init"

cd "$MAIN_REPO"
# shellcheck source=copilot-extensions/git-worktree/scripts/worktree-lib.sh
source "$LIB"

echo "── slug_from_branch ──"
assert_eq "simple name unchanged" "feature-auth" "$(slug_from_branch "feature-auth")"
assert_eq "slash replaced" "feature-auth-jwt" "$(slug_from_branch "feature/auth-jwt")"
assert_eq "special chars replaced" "my-branch-123" "$(slug_from_branch "my-branch-123")"
assert_eq "consecutive dashes collapsed" "feature-auth" "$(slug_from_branch "feature//auth")"
assert_eq "leading dashes removed" "branch" "$(slug_from_branch "--branch")"

echo "── git_root ──"
assert_eq "git_root returns repo path" "$MAIN_REPO" "$(git_root)"

echo "── repo_name ──"
assert_eq "repo_name returns dirname" "my-project" "$(repo_name)"

echo "── worktree_base_dir ──"
assert_eq "default base dir is .github/worktrees in main repo" "$MAIN_REPO/.github/worktrees" "$(worktree_base_dir)"
assert_eq "WORKTREE_BASE_DIR override" "/custom/path" "$(WORKTREE_BASE_DIR=/custom/path worktree_base_dir)"
assert_true "default_base_ref resolves something usable" test -n "$(default_base_ref)"

echo "── worktree helpers ──"
WT_PATH="$SCRATCH_ROOT/my-project-worktrees/test-branch"
mkdir -p "$(dirname "$WT_PATH")"
git worktree add -b test-branch "$WT_PATH" >/dev/null 2>&1

COUNT=$(list_worktrees | wc -l | tr -d ' ')
assert_eq "list_worktrees returns 1 entry" "1" "$COUNT"
assert_eq "worktree_path_for_branch finds linked worktree" "$WT_PATH" "$(worktree_path_for_branch "test-branch")"
assert_true "branch_exists sees created branch" branch_exists "test-branch"
assert_true "ref_exists sees HEAD" ref_exists "HEAD"
assert_true "is_worktree_path: exact match" is_worktree_path "$WT_PATH"
assert_true "is_worktree_path: subpath" is_worktree_path "$WT_PATH/src/file.txt"
assert_false "is_worktree_path: unrelated path" is_worktree_path "$SCRATCH_ROOT/other"
assert_false "is_worktree_path: empty string" is_worktree_path ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
