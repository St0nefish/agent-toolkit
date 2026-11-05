#!/usr/bin/env bash
# test-inbox-hook.sh — inbox hook dispatcher (SessionStart / UserPromptSubmit / Stop).
#
# Usage: bash tests/inbox/test-inbox-hook.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../../plugins-claude/inbox/scripts/inbox-hook.sh"
Q="$SCRIPT_DIR/../../plugins-claude/inbox/scripts/inbox"

PASS=0
FAIL=0
FILTER="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export INBOX_STATE_DIR="$TMP/state"
unset INBOX_SESSION

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
skip_filter() { [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; }
check() {
  if skip_filter "$1"; then return; fi
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "${3:-}"; fi
}

q() { bash "$Q" --session "$1" "${@:2}" >/dev/null; }
# hook <event> <session> [extra-json]: run the hook, set OUT/CODE.
hook() {
  local payload
  payload=$(jq -nc --arg e "$1" --arg s "$2" '{hook_event_name: $e, session_id: $s}')
  [[ -n "${3:-}" ]] && payload=$(jq -c ". + $3" <<<"$payload")
  CODE=0
  OUT=$(bash "$HOOK" <<<"$payload" 2>/dev/null) || CODE=$?
}

echo "inbox-hook"

# --- Stop matrix ---
hook Stop s-none
check "stop: no items -> silent" "$([[ $CODE -eq 0 && -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"

q s-dec add decision --title "Use sqlite" --chosen "sqlite"
hook Stop s-dec
check "stop: decisions only -> silent" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
q s-dec add decision --title "Name it widget" --chosen "widget"

q s-q add question --title "Delete prod table?"
hook Stop s-q '{"background_tasks":[]}'
msg=$(jq -r '.systemMessage // empty' <<<"$OUT")
check "stop: question, no bg -> INPUT NEEDED (1) + full list" "$([[ "$msg" == "🛑 INPUT NEEDED (1) · /inbox:questions"$'\n'"Q1 Delete prod table?"* ]] && echo 0 || echo 1)" "$msg"

hook Stop s-q '{"background_tasks":[{"id":"x"}]}'
msg=$(jq -r '.systemMessage // empty' <<<"$OUT")
check "stop: question + bg -> still working" "$([[ "$msg" == "⏳ 1 parked question(s), still working" ]] && echo 0 || echo 1)" "$msg"

q s-mix add question --title "First question"
q s-mix add question --title "Second unrelated thing"
q s-mix add decision --title "Decision one" --chosen a
hook Stop s-mix
msg=$(jq -r '.systemMessage // empty' <<<"$OUT")
check "stop: counts only questions" "$([[ "$(head -n1 <<<"$msg")" == "🛑 INPUT NEEDED (2) · /inbox:questions" && "$msg" != *"Decision one"* ]] && echo 0 || echo 1)" "$msg"

# --- UserPromptSubmit ---
hook UserPromptSubmit s-dec
check "prompt: decisions only -> silent" "$([[ -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"
hook UserPromptSubmit s-mix
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT")
check "prompt: questions -> ids line" "$([[ "$ctx" == *"Q1, Q2"* && "$ctx" != *"D1"* && "$ctx" == *"answer Q<n>"* ]] && echo 0 || echo 1)" "$ctx"

# --- SessionStart ---
hook SessionStart s-mix
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT")
check "session-start: begins with phrase" "$([[ "$ctx" == "Inbox tracker is active for this session."* ]] && echo 0 || echo 1)" "${ctx:0:60}"
check "session-start: command prefix with session id" "$([[ "$ctx" == *"inbox --session s-mix add question"* && "$ctx" == *"--session s-mix add decision"* && "$ctx" == *"--session s-mix answer Q<n>"* && "$ctx" == *"--session s-mix resolve D<n>"* ]] && echo 0 || echo 1)"
check "session-start: lists both kinds" "$([[ "$ctx" == *"First question"* && "$ctx" == *"Decision one"* ]] && echo 0 || echo 1)" "$ctx"

hook SessionStart s-empty
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT")
check "session-start: empty inbox omits open items" "$([[ "$ctx" == "Inbox tracker is active"* && "$ctx" != *"Open items"* ]] && echo 0 || echo 1)"

mkdir -p "$INBOX_STATE_DIR"
touch -d '30 days ago' "$INBOX_STATE_DIR/old-session.json"
hook SessionStart s-empty
check "session-start: prunes old state" "$([[ ! -e "$INBOX_STATE_DIR/old-session.json" ]] && echo 0 || echo 1)"

# A resumed session whose state file is past the prune window must keep its items.
q s-resumed add question --title "Survives resume"
touch -d '30 days ago' "$INBOX_STATE_DIR/s-resumed.json"
hook SessionStart s-resumed
ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT")
check "session-start: stale own session survives prune" "$([[ -e "$INBOX_STATE_DIR/s-resumed.json" && "$ctx" == *"Survives resume"* ]] && echo 0 || echo 1)" "$ctx"

# --- Robustness ---
CODE=0
OUT=$(echo '{"hook_event_name":"Stop"}' | bash "$HOOK" 2>/dev/null) || CODE=$?
check "missing session_id -> silent exit 0" "$([[ $CODE -eq 0 && -z "$OUT" ]] && echo 0 || echo 1)" "$OUT"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
