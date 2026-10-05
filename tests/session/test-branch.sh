#!/usr/bin/env bash
# test-branch.sh — tests for plugins-claude/session/scripts/branch
# Uses a hermetic temp git repo (real git, no mocks).
#
# Usage: bash tests/session/test-branch.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../plugins-claude/session/scripts/branch"

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
expect_rc() { # label, expected, actual
  if [[ "$2" -eq "$3" ]]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" commit -q --allow-empty -m init

run() { (cd "$REPO" && bash "$SCRIPT" "$@"); }
current() { git -C "$REPO" symbolic-ref --short HEAD; }

rc=0
run create feat/ok >/dev/null 2>&1 || rc=$?
expect_rc "valid create exits 0" 0 "$rc"
[[ "$(current)" == "feat/ok" ]] && ok "switched to new branch" || bad "switched to new branch"

orig="$(current)"
rc=0
run create "bad..name" >/dev/null 2>&1 || rc=$?
expect_rc "invalid name exits 1" 1 "$rc"
[[ "$(current)" == "$orig" ]] && ok "invalid name leaves branch unchanged" || bad "invalid name leaves branch unchanged"

rc=0
out=$(run create -- "-x" 2>&1) || rc=$?
expect_rc "dash-prefixed name rejected (--)" 1 "$rc"
rc=0
out=$(run create "-fbad" 2>&1) || rc=$?
expect_rc "dash-prefixed name rejected" 1 "$rc"
git -C "$REPO" show-ref --verify --quiet refs/heads/-fbad && bad "no dash branch created" || ok "no dash branch created"

rc=0
out=$(run create feat/ok 2>&1) || rc=$?
expect_rc "existing branch exits 2" 2 "$rc"
[[ "$out" == *"already exists"* ]] && ok "existing branch message" || bad "existing branch message: $out"

rc=0
run create >/dev/null 2>&1 || rc=$?
expect_rc "missing name exits 1" 1 "$rc"
rc=0
run >/dev/null 2>&1 || rc=$?
expect_rc "no args exits 1" 1 "$rc"
rc=0
run bogus >/dev/null 2>&1 || rc=$?
expect_rc "unknown subcommand exits 1" 1 "$rc"
rc=0
out=$(run -h 2>&1) || rc=$?
expect_rc "-h exits 0" 0 "$rc"
[[ "$out" == *Usage* ]] && ok "-h prints usage" || bad "-h prints usage"
rc=0
run --help >/dev/null 2>&1 || rc=$?
expect_rc "--help exits 0" 0 "$rc"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
