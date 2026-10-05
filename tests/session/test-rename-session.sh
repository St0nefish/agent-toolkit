#!/usr/bin/env bash
# test-rename-session.sh — tests for plugins-claude/session/scripts/rename-session
# Uses a temp fake $HOME with sessions/*.json and projects/<encoded>/*.jsonl.
#
# Usage: bash tests/session/test-rename-session.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../plugins-claude/session/scripts/rename-session"

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
check() { # label, condition-exit-status
  if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fresh fake HOME and a cwd with '.' and '_' in the path.
setup() {
  rm -rf "$TMP/home" "$TMP/work"
  HOME_DIR="$TMP/home"
  WORK="$TMP/work/.claude/worktrees/my_proj"
  mkdir -p "$HOME_DIR/.claude/sessions" "$WORK"
  WORK="$(cd "$WORK" && pwd -P)"
  ENC=$(printf '%s' "$WORK" | sed 's|[^A-Za-z0-9]|-|g')
  PROJ="$HOME_DIR/.claude/projects/$ENC"
  mkdir -p "$PROJ"
}

run() { (cd "$WORK" && HOME="$HOME_DIR" bash "$SCRIPT" "$@"); }

echo "=== encoded path / basic rename ==="
setup
echo '{"type":"user"}' >"$PROJ/sid-1.jsonl"
jq -n --arg c "$WORK" '{sessionId:"sid-1",cwd:$c,pid:999999}' >"$HOME_DIR/.claude/sessions/a.json"
rc=0
out=$(run "new-name" 2>&1) || rc=$?
check "exit 0 with encoded dir containing . and _" "$rc"
grep -q '"customTitle":"new-name"' "$PROJ/sid-1.jsonl" && r=0 || r=1
check "custom-title appended to JSONL" "$r"
[[ "$(jq -r .name "$HOME_DIR/.claude/sessions/a.json")" == "new-name" ]] && r=0 || r=1
check "PID file name patched" "$r"
[[ "$ENC" == *--claude-worktrees-my-proj ]] && r=0 || r=1
check "encoding turns '/.' and '_' into '-' ($ENC)" "$r"

echo "=== ancestor pid preference ==="
setup
echo '{}' >"$PROJ/sid-mine.jsonl"
echo '{}' >"$PROJ/sid-other.jsonl"
jq -n --arg c "$WORK" --argjson p "$$" '{sessionId:"sid-mine",cwd:$c,pid:$p}' >"$HOME_DIR/.claude/sessions/mine.json"
jq -n --arg c "$WORK" '{sessionId:"sid-other",cwd:$c,pid:999999}' >"$HOME_DIR/.claude/sessions/other.json"
touch -d '2030-01-01' "$HOME_DIR/.claude/sessions/other.json" # newer, but not an ancestor
touch -d '2020-01-01' "$HOME_DIR/.claude/sessions/mine.json"
run "picked" >/dev/null 2>&1 || true
[[ "$(jq -r .name "$HOME_DIR/.claude/sessions/mine.json")" == "picked" ]] && r=0 || r=1
check "ancestor-pid session chosen over newer one" "$r"
[[ "$(jq -r '.name // "none"' "$HOME_DIR/.claude/sessions/other.json")" == "none" ]] && r=0 || r=1
check "non-ancestor session untouched" "$r"

echo "=== newest mtime fallback ==="
setup
echo '{}' >"$PROJ/sid-old.jsonl"
echo '{}' >"$PROJ/sid-new.jsonl"
jq -n --arg c "$WORK" '{sessionId:"sid-old",cwd:$c,pid:999998}' >"$HOME_DIR/.claude/sessions/old.json"
jq -n --arg c "$WORK" '{sessionId:"sid-new",cwd:$c,pid:999999}' >"$HOME_DIR/.claude/sessions/new.json"
touch -d '2020-01-01' "$HOME_DIR/.claude/sessions/old.json"
touch -d '2030-01-01' "$HOME_DIR/.claude/sessions/new.json"
run "fallback" >/dev/null 2>&1 || true
[[ "$(jq -r .name "$HOME_DIR/.claude/sessions/new.json")" == "fallback" ]] && r=0 || r=1
check "newest session chosen when no ancestor matches" "$r"

echo "=== atomic rewrite preserves mode ==="
setup
echo '{}' >"$PROJ/sid-1.jsonl"
jq -n --arg c "$WORK" '{sessionId:"sid-1",cwd:$c,pid:999999}' >"$HOME_DIR/.claude/sessions/a.json"
chmod 640 "$HOME_DIR/.claude/sessions/a.json"
run "modetest" >/dev/null 2>&1 || true
[[ "$(stat -c %a "$HOME_DIR/.claude/sessions/a.json")" == "640" ]] && r=0 || r=1
check "mode preserved (640)" "$r"
left=$(find "$HOME_DIR/.claude/sessions" -name '*.XXXXXX' -o -name 'a.json.*' | wc -l)
[[ "$left" -eq 0 ]] && r=0 || r=1
check "no temp files left behind" "$r"

echo "=== failure paths ==="
setup
rc=0
run "x" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && r=0 || r=1
check "no session -> non-zero" "$r"
out=$(run "x" 2>&1 || true)
[[ "$out" == *"no active session found"* ]] && r=0 || r=1
check "no session -> clear message" "$r"
rc=0
run >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] && r=0 || r=1
check "missing name -> exit 1" "$r"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
