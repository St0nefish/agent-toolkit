#!/usr/bin/env bash
# test-extension.sh — Validate extension registration and suggestion logic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXT_DIR="$REPO_ROOT/.github/extensions/git-worktree"
EXT_FILE="$EXT_DIR/extension.mjs"

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

assert_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    ((FAIL++)) || true
  fi
}

EXT_CONTENT=$(cat "$EXT_FILE")

echo "── extension registration ──"
assert_contains "joins session" "joinSession" "$EXT_CONTENT"
assert_contains "registers onSessionStart" "onSessionStart" "$EXT_CONTENT"
assert_contains "registers onUserPromptSubmitted" "onUserPromptSubmitted" "$EXT_CONTENT"
assert_contains "registers status tool" "sf_git_worktree_status" "$EXT_CONTENT"
assert_contains "registers create tool" "sf_git_worktree_create" "$EXT_CONTENT"
assert_contains "registers remove tool" "sf_git_worktree_remove" "$EXT_CONTENT"
assert_contains "registers suggest tool" "sf_git_worktree_suggest" "$EXT_CONTENT"
assert_contains "uses session.log" "session.log" "$EXT_CONTENT"
assert_contains "prompt hook nudges suggest tool" "sf_git_worktree_suggest" "$EXT_CONTENT"
assert_contains "prompt hook nudges create tool" "sf_git_worktree_create" "$EXT_CONTENT"

if echo "$EXT_CONTENT" | grep -q 'console\.log'; then
  printf "  \033[31m✗\033[0m avoids console.log\n"
  ((FAIL++)) || true
else
  printf "  \033[32m✓\033[0m avoids console.log\n"
  ((PASS++)) || true
fi

echo "── syntax checks ──"
while IFS= read -r file; do
  assert_ok "$file parses" node --check "$file"
done < <(find "$EXT_DIR" -type f -name '*.mjs' | sort)

echo "── suggestion logic ──"
readarray -t RESULT < <(cd "$REPO_ROOT" && node --input-type=module <<'EOF_NODE'
import { promptHasExplicitWorktreeRequest, recommendBranchName, suggestWorktree } from './.github/extensions/git-worktree/lib/suggest.mjs';

const dirtyStatus = {
  currentCheckoutType: 'main',
  currentBranch: 'feature-auth',
  currentCheckout: { dirtyCount: 3 },
  linkedWorktrees: [],
  worktreeBaseDir: '/repo/.github/worktrees',
};

const explicit = suggestWorktree({
  prompt: 'run a docs hotfix in parallel without touching my current branch',
  status: dirtyStatus,
});
console.log(explicit.shouldSuggest ? 'yes' : 'no');
console.log(explicit.recommendedBranch);
console.log(explicit.recommendedSlug);

const related = suggestWorktree({
  prompt: 'finish the auth flow on this branch',
  status: dirtyStatus,
});
console.log(related.shouldSuggest ? 'yes' : 'no');
console.log(recommendBranchName('clean up markdown docs', ''));
console.log(promptHasExplicitWorktreeRequest('please do this in parallel') ? 'yes' : 'no');
console.log(promptHasExplicitWorktreeRequest('create a worktree for the auth fix') ? 'yes' : 'no');
console.log(promptHasExplicitWorktreeRequest('fix the auth tests') ? 'yes' : 'no');
EOF_NODE
)
assert_eq "explicit parallel request suggests worktree" "yes" "${RESULT[0]}"
assert_eq "explicit request uses bug/chore/wip prefix" "bug-run-docs-hotfix-parallel-without" "${RESULT[1]}"
assert_eq "slug mirrors recommended branch" "bug-run-docs-hotfix-parallel-without" "${RESULT[2]}"
assert_eq "related prompt stays on current branch" "no" "${RESULT[3]}"
assert_eq "docs prompt derives chore branch" "chore-clean-markdown-docs" "${RESULT[4]}"
assert_eq "explicit prompt matcher fires on parallel language" "yes" "${RESULT[5]}"
assert_eq "explicit prompt matcher fires on generic worktree request" "yes" "${RESULT[6]}"
assert_eq "explicit prompt matcher stays quiet on normal prompt" "no" "${RESULT[7]}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
