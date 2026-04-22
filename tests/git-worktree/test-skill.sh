#!/usr/bin/env bash
# test-skill.sh — Tests for the parallel-work skill.
#
# Skills are model instructions, not scripts, so we test:
#   1. Frontmatter structure (required fields, correct values)
#   2. Trigger keyword coverage (implicit + explicit triggers present)
#   3. Git commands prescribed by the skill (verify they work as expected
#      in the scenarios the skill describes)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../../plugins-copilot/git-worktree/skills/parallel-work/SKILL.md"

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

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (missing: %s)\n" "$label" "$needle"
    ((FAIL++)) || true
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (unexpected: %s)\n" "$label" "$needle"
    ((FAIL++)) || true
  fi
}

# ── 1. Frontmatter structure ──────────────────────────────────────────────────

echo "── skill frontmatter ──"

FRONTMATTER=$(awk '/^---$/{count++; if(count==2) exit} count==1' "$SKILL_FILE")
SKILL_CONTENT=$(cat "$SKILL_FILE")

assert_eq "name field" "parallel-work" \
  "$(echo "$FRONTMATTER" | grep '^name:' | awk '{print $2}')"

assert_eq "user-invocable is false" "false" \
  "$(echo "$FRONTMATTER" | grep 'user-invocable:' | awk '{print $2}')"

assert_contains "description mentions context mismatch" "unrelated" "$FRONTMATTER"
assert_contains "allowed-tools includes Bash" "Bash" "$FRONTMATTER"

# ── 2. Explicit trigger keywords ──────────────────────────────────────────────

echo "── explicit trigger keywords ──"

assert_contains "trigger: in parallel"            "in parallel"             "$SKILL_CONTENT"
assert_contains "trigger: without touching"       "without touching"        "$SKILL_CONTENT"
assert_contains "trigger: isolated environment"   "isolated environment"    "$SKILL_CONTENT"
assert_contains "trigger: background task"        "background task"         "$SKILL_CONTENT"

# ── 3. Implicit trigger criteria present ─────────────────────────────────────

echo "── implicit trigger (context-mismatch) coverage ──"

assert_contains "mentions uncommitted changes detection" "git status --short"   "$SKILL_CONTENT"
assert_contains "mentions unrelated changes condition"   "unrelated"            "$SKILL_CONTENT"
assert_contains "mentions hotfix scenario"               "hotfix"               "$SKILL_CONTENT"
assert_contains "rule: do not silently start work"       "silently"             "$SKILL_CONTENT"
assert_contains "mentions worktree list check"           "git worktree list"    "$SKILL_CONTENT"

# ── 4. Git commands work correctly in context-mismatch scenarios ───────────────
#
# These tests verify the actual git commands the skill prescribes
# produce meaningful output in the scenarios described.

echo "── git context-detection commands (scenario: clean repo) ──"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

REPO="$TMPDIR_BASE/my-project"
git init -q "$REPO"
git -C "$REPO" config user.email "test@test.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/README.md"
git -C "$REPO" add .
git -C "$REPO" commit -q -m "init"

cd "$REPO"

# Clean repo: git status --short should be empty
STATUS_CLEAN=$(git status --short)
assert_eq "clean repo: status is empty" "" "$STATUS_CLEAN"

# No linked worktrees: list should have exactly 1 line (main only in porcelain)
WT_COUNT=$(git worktree list --porcelain | grep -c "^worktree " || true)
assert_eq "clean repo: exactly 1 worktree (main)" "1" "$WT_COUNT"

echo "── git context-detection commands (scenario: dirty repo) ──"

# Simulate uncommitted changes (context-mismatch scenario)
echo "wip" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt

STATUS_DIRTY=$(git status --short)
assert_contains "dirty repo: status is non-empty" "feature.txt" "$STATUS_DIRTY"

BRANCH=$(git branch --show-current)
assert_eq "branch name is readable" "master" "$BRANCH"

# Verify worktree list still shows 1 (no linked worktrees yet)
WT_COUNT2=$(git worktree list --porcelain | grep -c "^worktree " || true)
assert_eq "dirty repo: still 1 worktree" "1" "$WT_COUNT2"

echo "── git context-detection commands (scenario: already in a worktree) ──"

# Create a linked worktree to simulate "already in worktree" guard
git stash -q
WT_PATH="$TMPDIR_BASE/my-project-worktrees/wt-branch"
mkdir -p "$(dirname "$WT_PATH")"
git worktree add -b wt-branch "$WT_PATH" -q

# From INSIDE the linked worktree, worktree list should show 2 entries
cd "$WT_PATH"
WT_COUNT3=$(git worktree list --porcelain | grep -c "^worktree " || true)
assert_eq "inside linked worktree: 2 entries in list" "2" "$WT_COUNT3"

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
