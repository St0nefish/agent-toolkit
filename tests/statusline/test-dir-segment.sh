#!/usr/bin/env bash
# test-dir-segment.sh — Tests for the statusline `dir` segment helpers.
# Covers shorten_path() display logic (including the name override that fixes
# #126) and resolve_project_name(), which derives the canonical project name and
# must return the MAIN repo name when PROJECT_DIR is a linked git worktree.
#
# Usage: bash tests/statusline/test-dir-segment.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../../plugins-claude/statusline/scripts/statusline.sh"

# Source the script for direct function access. The `main` call is guarded by a
# BASH_SOURCE check, so sourcing defines functions without rendering a statusline.
# Point XDG dirs at a scratch location and feed empty stdin to avoid touching the
# real config/cache or reading the terminal.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
# shellcheck source=/dev/null
source "$STATUSLINE" </dev/null

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

filtered() {
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

check() {
  local label="$1" expected="$2" actual="$3"
  if filtered "$label"; then
    ((SKIP++)) || true
    return 0
  fi
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: %q, got: %q)\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

# Run shorten_path with a controlled HOME so tilde substitution is deterministic.
sp() {
  local home="$1"
  shift
  (
    export HOME="$home"
    shorten_path "$@"
  )
}

# ===== shorten_path display logic =====
echo "── shorten_path ──"

check "project root → bare name" "proj" \
  "$(sp /home/u /home/u/proj 40 /home/u/proj)"

check "subdir → name/abbreviated middle" "proj/p/statusline" \
  "$(sp /home/u /home/u/proj/plugins-claude/statusline 40 /home/u/proj)"

check "name_override replaces basename" "realproj" \
  "$(sp /home/u /home/u/proj-wt 40 /home/u/proj-wt realproj)"

check "name_override applies to subdir too" "realproj/p/statusline" \
  "$(sp /home/u /home/u/proj-wt/plugins-claude/statusline 40 /home/u/proj-wt realproj)"

check "path outside project → full path, home as ~" "~/elsewhere/x" \
  "$(sp /home/u /home/u/elsewhere/x 40 /home/u/proj)"

check "no project → full path, home as ~" "~/elsewhere" \
  "$(sp /home/u /home/u/elsewhere 40 "")"

check "over-length display left-truncated with …" "…ongsubdir" \
  "$(sp /home/u /home/u/proj/verylongsubdir 10 /home/u/proj)"

# ===== resolve_project_name =====
echo "── resolve_project_name ──"

# Build a real git repo plus a linked worktree in the scratch dir.
REPO="$TMP/myrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name "Test"
git -C "$REPO" commit -q --allow-empty -m "init"
WT="$TMP/myrepo-feature-x"
git -C "$REPO" worktree add -q "$WT" 2>/dev/null

resolve() {
  local out rc
  out=$(resolve_project_name "$1") && rc=0 || rc=$?
  RES_OUT="$out"
  RES_RC="$rc"
}

resolve "$REPO"
check "main checkout → repo basename" "myrepo" "$RES_OUT"
check "main checkout → rc 0" "0" "$RES_RC"

resolve "$WT"
check "linked worktree → MAIN repo name (not worktree dir)" "myrepo" "$RES_OUT"
check "linked worktree → rc 0" "0" "$RES_RC"

NONGIT="$TMP/plain-dir"
mkdir -p "$NONGIT"
resolve "$NONGIT"
check "non-git dir → empty output" "" "$RES_OUT"
check "non-git dir → rc 1 (fallback)" "1" "$RES_RC"

resolve ""
check "empty dir arg → rc 1" "1" "$RES_RC"

# ===== Summary =====
echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
