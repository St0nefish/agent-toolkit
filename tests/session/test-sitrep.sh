#!/usr/bin/env bash
# test-sitrep.sh — tests for plugins-claude/session/scripts/sitrep
# Uses hermetic temp git repos (real git, no mocks).
#
# Usage: bash tests/session/test-sitrep.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../plugins-claude/session/scripts/sitrep"

PASS=0
FAIL=0
ok() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}
bad() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
has() { # label, haystack, needle
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1 (missing '$3')"; fi
}
hasnt() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1 (unexpected '$3')"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

g() { git -C "$REPO" "$@"; }

new_repo() {
  REPO="$TMP/$1"
  git init -q -b main "$REPO"
  echo base >"$REPO/base.txt"
  g add base.txt
  g commit -q -m "base commit"
}

echo "=== help ==="
rc=0
out=$(bash "$SCRIPT" -h 2>&1) || rc=$?
[[ "$rc" -eq 0 ]] && ok "-h exits 0" || bad "-h exits 0 (got $rc)"
has "-h prints usage" "$out" "Usage: sitrep"

echo "=== dirty tree still shows committed info ==="
new_repo dirty
g switch -q -c feature
echo feat >"$REPO/feat.txt"
g add feat.txt
g commit -q -m "feature commit"
echo more >>"$REPO/base.txt"
echo new >"$REPO/untracked.txt"
out=$(bash "$SCRIPT" "$REPO" 2>&1)
has "base detected" "$out" "base: main"
has "ahead shown" "$out" "ahead: 1"
has "unstaged section" "$out" "=== UNSTAGED ==="
has "untracked section" "$out" "=== UNTRACKED ==="
has "branch commits shown with dirty tree" "$out" "=== BRANCH COMMITS ==="
has "feature commit listed" "$out" "feature commit"
has "committed diff shown with dirty tree" "$out" "=== COMMITTED DIFF ==="

echo "=== no upstream ==="
hasnt "no UNPUSHED without upstream" "$out" "=== UNPUSHED ==="

echo "=== unpushed with upstream ==="
new_repo up
git init -q --bare "$TMP/up-remote.git"
g remote add origin "$TMP/up-remote.git"
g push -q -u origin main 2>/dev/null
echo x >"$REPO/x.txt"
g add x.txt
g commit -q -m "local only"
echo dirty >>"$REPO/base.txt"
out=$(bash "$SCRIPT" "$REPO" 2>&1)
has "UNPUSHED shown alongside dirty tree" "$out" "=== UNPUSHED ==="
has "unpushed commit listed" "$out" "local only"

echo "=== diff cap ==="
new_repo cap
seq 1 50 >"$REPO/big.txt"
g add big.txt
out=$(SITREP_MAX_DIFF_LINES=10 bash "$SCRIPT" "$REPO" 2>&1)
has "truncation note" "$out" "[truncated "
lines=$(printf '%s\n' "$out" | awk '/=== STAGED DIFF ===/{f=1;next} f' | wc -l)
[[ "$lines" -le 12 ]] && ok "staged diff capped ($lines lines)" || bad "staged diff capped ($lines lines)"
out=$(bash "$SCRIPT" "$REPO" 2>&1)
hasnt "no truncation under default cap" "$out" "[truncated "

echo "=== base detection prefers origin/HEAD ==="
new_repo oh
git init -q --bare "$TMP/oh-remote.git"
g remote add origin "$TMP/oh-remote.git"
g push -q origin main 2>/dev/null
g branch -q trunk
g push -q origin trunk 2>/dev/null
g remote set-head origin trunk >/dev/null 2>&1
g switch -q -c topic
echo t >"$REPO/t.txt"
g add t.txt
g commit -q -m "topic commit"
out=$(bash "$SCRIPT" "$REPO" 2>&1)
has "origin/HEAD used as base" "$out" "base: origin/trunk"

echo "=== no merge base ==="
new_repo nomb
g switch -q --orphan lonely
echo o >"$REPO/o.txt"
g add o.txt
g commit -q -m "orphan commit"
out=$(bash "$SCRIPT" "$REPO" 2>&1)
has "no merge base noted" "$out" "no merge base"
has "orphan commits still listed" "$out" "orphan commit"

echo "=== not a git repo ==="
mkdir "$TMP/plain"
out=$(bash "$SCRIPT" "$TMP/plain" 2>&1)
has "non-repo reported" "$out" "is_git_repo: false"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
