#!/usr/bin/env bash
#
# test-command-docs.sh — Checks that Copilot-facing git-worktree docs avoid
# relying on COPILOT_PLUGIN_ROOT inside Bash examples and describe the direct
# git worktree flows the agent should use.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../../plugins-copilot/git-worktree"

PASS=0
FAIL=0

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

echo "── skill docs avoid plugin-root bash paths ──"

LIST_DOC=$(cat "$PLUGIN_DIR/skills/worktree-list/SKILL.md")
CREATE_DOC=$(cat "$PLUGIN_DIR/skills/worktree-create/SKILL.md")
REMOVE_DOC=$(cat "$PLUGIN_DIR/skills/worktree-remove/SKILL.md")
PARALLEL_DOC=$(cat "$PLUGIN_DIR/skills/worktree-parallel-work/SKILL.md")

assert_not_contains "worktree-list skill avoids COPILOT_PLUGIN_ROOT" '${COPILOT_PLUGIN_ROOT}' "$LIST_DOC"
assert_not_contains "worktree-create skill avoids COPILOT_PLUGIN_ROOT" '${COPILOT_PLUGIN_ROOT}' "$CREATE_DOC"
assert_not_contains "worktree-remove skill avoids COPILOT_PLUGIN_ROOT" '${COPILOT_PLUGIN_ROOT}' "$REMOVE_DOC"
assert_not_contains "worktree-parallel-work skill avoids COPILOT_PLUGIN_ROOT" '${COPILOT_PLUGIN_ROOT}' "$PARALLEL_DOC"

echo "── skill docs describe direct git worktree flows ──"

assert_contains "worktree-list skill uses git worktree list" 'git worktree list --porcelain' "$LIST_DOC"
assert_contains "worktree-create skill uses git worktree add" 'git worktree add <path>' "$CREATE_DOC"
assert_contains "worktree-create skill derives repo root" 'git rev-parse --show-toplevel' "$CREATE_DOC"
assert_contains "worktree-remove skill uses git worktree remove" 'git worktree remove <path>' "$REMOVE_DOC"
assert_contains "worktree-remove skill uses git worktree list" 'git worktree list --porcelain' "$REMOVE_DOC"
assert_contains "worktree-parallel-work skill points at create flow" 'git worktree add' "$PARALLEL_DOC"
assert_contains "worktree-parallel-work skill points at remove flow" 'git worktree remove' "$PARALLEL_DOC"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
