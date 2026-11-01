#!/usr/bin/env bash
# test-notify-on-stop.sh — Stop-hook notification logic, incl. "Input needed".
#
# Usage: bash tests/notify-on-stop/test-notify-on-stop.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../../plugins-claude/notify-on-stop/scripts/notify-on-stop.sh"
Q="$SCRIPT_DIR/../../utils/questions"

PASS=0
FAIL=0
FILTER="${1:-}"

if [[ "$(uname)" == "Darwin" ]]; then
  echo "  (skipped: notify-send dispatch is Linux-only)"
  exit 0
fi

TMP=$(mktemp -d)
MOCK="$TMP/bin"
mkdir -p "$MOCK"
trap 'rm -rf "$TMP" /tmp/claude-notify-nos-test-*' EXIT
export QUESTIONS_STATE_DIR="$TMP/state"
unset QUESTIONS_SESSION

# Fake notify-send: records its args (one per line) to $NOTIFY_LOG.
export NOTIFY_LOG="$TMP/notify.log"
cat > "$MOCK/notify-send" <<'MOCKEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$NOTIFY_LOG"
MOCKEOF
chmod +x "$MOCK/notify-send"
export PATH="$MOCK:$PATH"

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

# fresh <sid>: clear logs/state for a session
fresh() {
  rm -rf "$QUESTIONS_STATE_DIR"
  rm -f "$NOTIFY_LOG" "/tmp/claude-notify-$1"
}

# run_hook <payload-json>
run_hook() { echo "$1" | bash "$HOOK" >/dev/null 2>&1 || true; }

stop_payload() { # sid [bg-json]
  jq -nc --arg sid "$1" --argjson bg "${2:-null}" \
    '{hook_event_name:"Stop", session_id:$sid, cwd:"/work/myproj", last_assistant_message:"all done"}
     + (if $bg == null then {} else {background_tasks:$bg} end)'
}

park() { bash "$Q" --session "$1" add --new --title "$2" >/dev/null 2>&1; }

logged() { [[ -f "$NOTIFY_LOG" ]] && cat "$NOTIFY_LOG" || true; }

echo "── input needed ──"
sid="nos-test-1"
fresh "$sid"
park "$sid" "Which db?"
park "$sid" "Which port?"
run_hook "$(stop_payload "$sid")"
out=$(logged)
check "open>0, bg absent: Input needed with no state file" \
  "$(grep -qx 'Input needed' <<<"$out" && echo 0 || echo 1)" "log=$out"
check "body has project and count" \
  "$(grep -qx 'myproj: 2 question(s) awaiting you' <<<"$out" && echo 0 || echo 1)" "log=$out"

fresh "$sid"
park "$sid" "Which db?"
date +%s > "/tmp/claude-notify-$sid"
run_hook "$(stop_payload "$sid" '[]')"
check "open>0, bg empty, under threshold: still notifies" \
  "$(grep -qx 'Input needed' <<<"$(logged)" && echo 0 || echo 1)"

fresh "$sid"
park "$sid" "Which db?"
run_hook "$(stop_payload "$sid" '[]' | jq -c '. + {stop_hook_active:true}')"
check "stop_hook_active suppresses" "$([[ ! -s "$NOTIFY_LOG" ]] && echo 0 || echo 1)"

fresh "$sid"
park "$sid" "Which db?"
stop_payload "$sid" | jq -c 'del(.session_id) + {sessionId:"'"$sid"'"}' \
  | bash "$HOOK" >/dev/null 2>&1 || true
check "sessionId (Copilot) accepted" \
  "$(grep -qx 'Input needed' <<<"$(logged)" && echo 0 || echo 1)"

echo "── background tasks present ──"
fresh "$sid"
park "$sid" "Which db?"
date +%s > "/tmp/claude-notify-$sid"
run_hook "$(stop_payload "$sid" '[{"id":"b1"}]')"
check "open>0, bg>0, under threshold: silent" "$([[ ! -s "$NOTIFY_LOG" ]] && echo 0 || echo 1)" "log=$(logged)"

fresh "$sid"
park "$sid" "Which db?"
echo $(( $(date +%s) - 100 )) > "/tmp/claude-notify-$sid"
run_hook "$(stop_payload "$sid" '[{"id":"b1"}]')"
out=$(logged)
check "open>0, bg>0, over threshold: normal notification" \
  "$(grep -qx 'Task complete' <<<"$out" && ! grep -q 'Input needed' <<<"$out" && echo 0 || echo 1)" "log=$out"

echo "── no open questions ──"
fresh "$sid"
date +%s > "/tmp/claude-notify-$sid"
run_hook "$(stop_payload "$sid")"
check "open==0, under threshold: silent" "$([[ ! -s "$NOTIFY_LOG" ]] && echo 0 || echo 1)"

fresh "$sid"
run_hook "$(stop_payload "$sid")"
check "open==0, no state file: silent" "$([[ ! -s "$NOTIFY_LOG" ]] && echo 0 || echo 1)"

fresh "$sid"
echo $(( $(date +%s) - 100 )) > "/tmp/claude-notify-$sid"
run_hook "$(stop_payload "$sid")"
out=$(logged)
check "open==0, over threshold: normal notification" \
  "$(grep -qx 'Task complete' <<<"$out" && grep -qx 'myproj: all done' <<<"$out" && echo 0 || echo 1)" "log=$out"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
