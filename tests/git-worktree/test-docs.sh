#!/usr/bin/env bash
# test-docs.sh — Validate migrated docs and references.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
README_CONTENT=$(cat "$REPO_ROOT/README.md")
CLAUDE_CONTENT=$(cat "$REPO_ROOT/CLAUDE.md")
SESSION_START=$(cat "$REPO_ROOT/plugins-copilot/session/commands/session-start.md")
SESSION_ISSUE=$(cat "$REPO_ROOT/plugins-copilot/session/commands/session-issue.md")
SESSION_ORCH=$(cat "$REPO_ROOT/plugins-copilot/session/commands/session-orchestrate.md")
SESSION_END=$(cat "$REPO_ROOT/plugins-copilot/session/commands/session-end.md")
AUTO_SESSION=$(cat "$REPO_ROOT/plugins-claude/auto-session-title/README.md")
MARKETPLACE=$(cat "$REPO_ROOT/.github/plugin/marketplace.json")

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

echo "── root docs ──"
assert_contains "README lists extension" "copilot-extensions/git-worktree/" "$README_CONTENT"
assert_contains "README documents install one-liner" "install-copilot-git-worktree.sh | bash" "$README_CONTENT"
assert_contains "README documents seeded approvals" "seeds Copilot's persisted tool approvals" "$README_CONTENT"
assert_contains "extension docs mention helper command" "copilot-git-worktree-allow" "$README_CONTENT"
assert_contains "CLAUDE documents extensions tree" "copilot-extensions/" "$CLAUDE_CONTENT"
assert_contains "CLAUDE says git-worktree is an extension" 'git-worktree` extension' "$CLAUDE_CONTENT"

echo "── session docs ──"
assert_contains "session-start uses native create tool" "sf_git_worktree_create" "$SESSION_START"
assert_contains "session-issue uses native create tool" "sf_git_worktree_create" "$SESSION_ISSUE"
assert_contains "session-orchestrate uses native create tool" "sf_git_worktree_create" "$SESSION_ORCH"
assert_contains "session-end uses native remove tool" "sf_git_worktree_remove" "$SESSION_END"
assert_contains "auto-session-title references extension" "Copilot extension" "$AUTO_SESSION"

echo "── retired plugin surface removed ──"
assert_not_contains "README no longer links old plugin dir" "plugins-copilot/git-worktree" "$README_CONTENT"
assert_not_contains "marketplace no longer lists git-worktree plugin" '"name": "git-worktree"' "$MARKETPLACE"
STALE=$(cd "$REPO_ROOT" && rg -n "plugins-copilot/git-worktree|git-worktree plugin|worktree-whitelist.sh|/worktree-create|/worktree-remove|worktree-parallel-work" README.md CLAUDE.md plugins-copilot/session plugins-claude/auto-session-title .github 2>/dev/null || true)
if [[ -z "$STALE" ]]; then
  printf "  \033[32m✓\033[0m no stale plugin references in migrated surfaces\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m stale plugin references remain\n%s\n" "$STALE"
  ((FAIL++)) || true
fi

echo "── repo-local discovery removed ──"
assert_not_contains "README no longer advertises project-scoped extension" ".github/extensions/git-worktree/" "$README_CONTENT"
assert_not_contains "CLAUDE no longer documents project extension path" ".github/extensions/git-worktree/" "$CLAUDE_CONTENT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
