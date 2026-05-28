#!/usr/bin/env bash
# test-worktree-cleanup.sh — Validate the git worktree-detection and cleanup
# recipe embedded in the `ship` skill (plugins-claude/git-tools/skills/ship/SKILL.md,
# step 0 detection + step 7 Case B). The skill is Markdown, so this test re-runs
# the same plain-git commands in throwaway repos to catch git-behavior regressions.
#
# Usage: bash tests/git-tools/test-worktree-cleanup.sh

set -euo pipefail

# Hermetic git: ignore the developer's global/system config (gpgsign, templates,
# init.defaultBranch, …) so commits and branch names are deterministic in CI.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

PASS=0
FAIL=0
SKIP=0

# realpath the temp root: on macOS $TMPDIR/mktemp live under /var → /private/var,
# so the detection's realpath compare needs a normalized base to avoid a false
# "linked" reading in the main checkout.
TMP_ROOT=$(realpath "$(mktemp -d)")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  FAIL=$((FAIL + 1))
}

# Create a main repo with one commit on branch `main`. Echoes its absolute path.
new_repo() {
  local d="$TMP_ROOT/$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "Test"
  printf 'seed\n' >"$d/file.txt"
  git -C "$d" add file.txt
  git -C "$d" commit -q -m "init"
  echo "$d"
}

# The detection recipe, exactly as written in the skill. Echoes "linked" or "main".
detect() {
  local gd gcd
  gd=$(git rev-parse --git-dir)
  gcd=$(git rev-parse --git-common-dir)
  if [ "$(realpath "$gd")" != "$(realpath "$gcd")" ]; then
    echo linked
  else
    echo main
  fi
}

# The main-worktree-path extraction recipe from the skill.
main_wt_path() {
  git worktree list --porcelain | awk 'NR==1 && /^worktree /{sub(/^worktree /,""); print}'
}

echo "── worktree detection ──"

# Test 1: main checkout → detection reports "main"
main=$(new_repo t1-main)
got=$(cd "$main" && detect)
if [ "$got" = "main" ]; then
  pass "main checkout detected as 'main'"
else
  fail "main checkout detection" "got '$got'"
fi

# Test 2: linked worktree → detection reports "linked"
main=$(new_repo t2-main)
wt="$TMP_ROOT/t2-wt"
git -C "$main" worktree add -q "$wt" -b feat/x
got=$(cd "$wt" && detect)
if [ "$got" = "linked" ]; then
  pass "linked worktree detected as 'linked'"
else
  fail "linked worktree detection" "got '$got'"
fi

# Test 3: main-path extraction from inside the linked worktree
got=$(cd "$wt" && main_wt_path)
if [ "$(realpath "$got")" = "$(realpath "$main")" ]; then
  pass "main worktree path extracted from porcelain"
else
  fail "main worktree path extraction" "got '$got' want '$main'"
fi

echo "── cleanliness gate ──"

# Test 4: clean → empty status; dirty (untracked) → non-empty status
if [ -z "$(git -C "$wt" status --porcelain)" ]; then
  pass "clean worktree → empty status --porcelain"
else
  fail "clean worktree status" "expected empty"
fi
touch "$wt/untracked.txt"
if [ -n "$(git -C "$wt" status --porcelain)" ]; then
  pass "dirty worktree → non-empty status --porcelain"
else
  fail "dirty worktree status" "expected non-empty"
fi

echo "── full clean cleanup (merge-commit) ──"

# Test 5: merge feat into main, then remove worktree + prune + branch -d
main=$(new_repo t5-main)
wt="$TMP_ROOT/t5-wt"
git -C "$main" worktree add -q "$wt" -b feat/y
printf 'change\n' >>"$wt/file.txt"
git -C "$wt" commit -q -am "feat work"
git -C "$main" merge -q --no-ff -m "merge feat/y" feat/y
git -C "$main" worktree remove "$wt"
git -C "$main" worktree prune
git -C "$main" branch -d feat/y >/dev/null 2>&1
remaining=$(git -C "$main" worktree list --porcelain | grep -c '^worktree ')
if [ ! -e "$wt" ]; then
  pass "git worktree remove deleted the worktree directory"
else
  fail "worktree remove" "directory still exists"
fi
if [ "$remaining" -eq 1 ]; then
  pass "only the main worktree remains after cleanup"
else
  fail "worktree list after cleanup" "expected 1, got $remaining"
fi
if [ -z "$(git -C "$main" branch --list feat/y)" ]; then
  pass "merged branch deleted with 'git branch -d'"
else
  fail "branch -d after merge" "feat/y still present"
fi

echo "── squash-merge caveat ──"

# Test 6: squash merge → branch tip not an ancestor → 'git branch -d' refuses;
# 'git branch -D' force-deletes.
main=$(new_repo t6-main)
wt="$TMP_ROOT/t6-wt"
git -C "$main" worktree add -q "$wt" -b feat/z
printf 'squashed change\n' >>"$wt/file.txt"
git -C "$wt" commit -q -am "feat work to squash"
git -C "$main" merge -q --squash feat/z
git -C "$main" commit -q -m "squash merge feat/z"
git -C "$main" worktree remove "$wt"
if git -C "$main" branch -d feat/z >/dev/null 2>&1; then
  fail "branch -d after squash" "expected refusal, but it succeeded"
else
  pass "'git branch -d' refuses an unmerged (squashed) branch"
fi
if git -C "$main" branch -D feat/z >/dev/null 2>&1 &&
  [ -z "$(git -C "$main" branch --list feat/z)" ]; then
  pass "'git branch -D' force-deletes the squashed branch"
else
  fail "branch -D after squash" "force delete did not remove feat/z"
fi

echo "── detached HEAD ──"

# Test 7: detached worktree → abbrev-ref HEAD is literal "HEAD" (skip branch delete)
main=$(new_repo t7-main)
wt="$TMP_ROOT/t7-wt"
git -C "$main" worktree add -q --detach "$wt"
ref=$(cd "$wt" && git rev-parse --abbrev-ref HEAD)
if [ "$ref" = "HEAD" ]; then
  pass "detached worktree → abbrev-ref HEAD == 'HEAD' (branch delete skipped)"
else
  fail "detached HEAD detection" "got '$ref'"
fi

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[ "$FAIL" -eq 0 ] || exit 1
