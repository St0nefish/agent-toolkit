#!/usr/bin/env bash
# test-create-remove.sh — Integration tests for the git-worktree extension scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CREATE_SCRIPT="$REPO_ROOT/copilot-extensions/git-worktree/scripts/worktree-create.sh"
REMOVE_SCRIPT="$REPO_ROOT/copilot-extensions/git-worktree/scripts/worktree-remove.sh"
LIST_SCRIPT="$REPO_ROOT/copilot-extensions/git-worktree/scripts/worktree-list.sh"
SCRATCH_ROOT="$REPO_ROOT/.scratch-tests/git-worktree/test-create-remove-$$"

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

assert_output_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (missing: %s)\n" "$label" "$needle"
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
export WORKTREE_BASE_DIR="$SCRATCH_ROOT/my-project-worktrees"

echo "── worktree-create.sh ──"
WT_PATH="$WORKTREE_BASE_DIR/feature-auth"
CREATE_OUTPUT=$(bash "$CREATE_SCRIPT" "feature/auth" 2>&1)
if [[ $? -eq 0 ]]; then
  printf "  \033[32m✓\033[0m %s\n" "create new worktree"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s (command failed)\n" "create new worktree"
  ((FAIL++)) || true
fi
assert_dir_exists "worktree directory created" "$WT_PATH"
assert_ok "branch exists in worktree" git -C "$WT_PATH" rev-parse --verify "refs/heads/feature/auth"
assert_output_contains "create output reports path" "Path: $WT_PATH" "$CREATE_OUTPUT"
assert_output_contains "create output reports usage" "Use it with: cd $WT_PATH" "$CREATE_OUTPUT"
assert_fail "create duplicate fails" bash "$CREATE_SCRIPT" "feature/auth"

echo "── explicit base branch ──"
git checkout -q -b release/base
echo "release" >"$MAIN_REPO/release.txt"
git -C "$MAIN_REPO" add release.txt
git -C "$MAIN_REPO" commit -q -m "release base"
git checkout -q -
EXPLICIT_OUTPUT=$(bash "$CREATE_SCRIPT" "feature/from-base" --from "release/base" 2>&1)
WT_BASE_PATH="$WORKTREE_BASE_DIR/feature-from-base"
assert_dir_exists "explicit-base worktree created" "$WT_BASE_PATH"
assert_output_contains "explicit base reported" "Base: explicit base release/base" "$EXPLICIT_OUTPUT"
assert_ok "explicit-base worktree contains base file" test -f "$WT_BASE_PATH/release.txt"

echo "── branch already checked out elsewhere ──"
MANUAL_PATH="$SCRATCH_ROOT/manual-existing"
git worktree add -q "$MANUAL_PATH" -b "feature/existing"
EXISTING_OUTPUT=$(bash "$CREATE_SCRIPT" "feature/existing" 2>&1 || true)
assert_output_contains "existing branch reports occupied worktree" "already checked out in another worktree: $MANUAL_PATH" "$EXISTING_OUTPUT"

echo "── occupied target path ──"
mkdir -p "$WORKTREE_BASE_DIR/feature-path-conflict"
PATH_CONFLICT_OUTPUT=$(bash "$CREATE_SCRIPT" "feature/path-conflict" 2>&1 || true)
assert_output_contains "occupied path reports blocking error" "target worktree path already exists: $WORKTREE_BASE_DIR/feature-path-conflict" "$PATH_CONFLICT_OUTPUT"

echo "── worktree-list.sh ──"
OUTPUT=$(bash "$LIST_SCRIPT" 2>/dev/null)
if echo "$OUTPUT" | grep -q "feature/auth"; then
  printf "  \033[32m✓\033[0m list shows created worktree\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m list does not show created worktree\n"
  ((FAIL++)) || true
fi

echo "── worktree-remove.sh ──"
assert_ok "remove by slug" bash "$REMOVE_SCRIPT" "feature-auth"
assert_dir_gone "worktree directory removed" "$WT_PATH"
assert_ok "remove explicit-base worktree by slug" bash "$REMOVE_SCRIPT" "feature-from-base"
assert_dir_gone "explicit-base worktree removed" "$WT_BASE_PATH"
assert_fail "remove non-existent worktree fails" bash "$REMOVE_SCRIPT" "nonexistent"

echo "── create → remove --delete-branch ──"
bash "$CREATE_SCRIPT" "cleanup-test" >/dev/null 2>&1
WT2_PATH="$WORKTREE_BASE_DIR/cleanup-test"
assert_dir_exists "second worktree created" "$WT2_PATH"
assert_ok "remove with --delete-branch" bash "$REMOVE_SCRIPT" "cleanup-test" --delete-branch
assert_dir_gone "second worktree removed" "$WT2_PATH"
if ! git rev-parse --verify "refs/heads/cleanup-test" >/dev/null 2>&1; then
  printf "  \033[32m✓\033[0m branch deleted after --delete-branch\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m branch still exists after --delete-branch\n"
  ((FAIL++)) || true
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
