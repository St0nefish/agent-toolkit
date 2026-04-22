#!/usr/bin/env bash
# test-whitelist.sh — Tests for worktree-whitelist.sh hook.
# Verifies that git worktree management commands are auto-allowed,
# and that operations targeting registered worktree paths are auto-allowed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../plugins-copilot/git-worktree/scripts/worktree-whitelist.sh"

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

make_bash_payload() {
  local cmd="$1"
  local args_json
  args_json=$(jq -n --arg c "$cmd" '{"command":$c}' | jq -c '.')
  jq -n --arg t "bash" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}'
}

make_file_payload() {
  local tool="$1" path="$2"
  local args_json
  args_json=$(jq -n --arg p "$path" '{"file_path":$p}' | jq -c '.')
  jq -n --arg t "$tool" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}'
}

run_test() {
  local expected="$1" label="$2"
  shift 2
  local payload="$1"

  local raw result
  raw=$(echo "$payload" | bash "$HOOK_SCRIPT" 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    result="none"
  else
    result=$(echo "$raw" | jq -r '.permissionDecision // "none"' 2>/dev/null || echo "none")
  fi

  if [[ "$result" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "$expected" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "$expected" "$label" "$result"
    ((FAIL++)) || true
  fi
}

# ── Setup: temp git repo with a real worktree ─────────────────────────────────

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

MAIN_REPO="$TMPDIR_BASE/main-repo"
WORKTREE_DIR="$TMPDIR_BASE/main-repo-worktrees"
WORKTREE_PATH="$WORKTREE_DIR/test-branch"

# Create a minimal git repo
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" config user.email "test@test.com"
git -C "$MAIN_REPO" config user.name "Test"
echo "init" > "$MAIN_REPO/README.md"
git -C "$MAIN_REPO" add .
git -C "$MAIN_REPO" commit -q -m "init"

# Create a linked worktree
mkdir -p "$WORKTREE_DIR"
git -C "$MAIN_REPO" worktree add -b test-branch "$WORKTREE_PATH" >/dev/null 2>&1

# ── Tests: must run from inside the git repo ──────────────────────────────────

cd "$MAIN_REPO"

echo "── git worktree management commands (allow) ──"

run_test allow "git worktree add ../wt test-branch" \
  "$(make_bash_payload "git worktree add ../wt test-branch")"

run_test allow "git worktree remove ../wt" \
  "$(make_bash_payload "git worktree remove ../wt")"

run_test allow "git worktree prune" \
  "$(make_bash_payload "git worktree prune")"

run_test allow "git worktree list" \
  "$(make_bash_payload "git worktree list")"

run_test allow "git worktree move ../wt ../new-wt" \
  "$(make_bash_payload "git worktree move ../wt ../new-wt")"

run_test allow "git worktree lock ../wt" \
  "$(make_bash_payload "git worktree lock ../wt")"

run_test allow "git worktree repair" \
  "$(make_bash_payload "git worktree repair")"

echo "── bash commands referencing a worktree path (allow) ──"

run_test allow "bash cd into worktree" \
  "$(make_bash_payload "cd $WORKTREE_PATH && git status")"

run_test allow "bash command with worktree path" \
  "$(make_bash_payload "ls $WORKTREE_PATH/src")"

echo "── file operations targeting worktree path (allow) ──"

run_test allow "Edit in worktree" \
  "$(make_file_payload "edit" "$WORKTREE_PATH/file.txt")"

run_test allow "Write in worktree subdir" \
  "$(make_file_payload "write" "$WORKTREE_PATH/src/main.js")"

echo "── unrelated commands (fall-through, no opinion) ──"

run_test none "unrelated bash command" \
  "$(make_bash_payload "ls -la")"

run_test none "unrelated git command" \
  "$(make_bash_payload "git status")"

run_test none "file outside worktree" \
  "$(make_file_payload "edit" "/tmp/other-file.txt")"

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
