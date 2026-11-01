#!/usr/bin/env bash
# Hook dispatcher for the questions plugin (SessionStart / UserPromptSubmit / Stop).
# Reads the hook payload on stdin; prints only a JSON object (or nothing) on stdout.
set -uo pipefail

INPUT=$(cat)
SELF=$(readlink -f "$0")
Q="$(dirname "$SELF")/questions"

event=$(jq -r '.hook_event_name // empty' <<<"$INPUT")
sid=$(jq -r '.session_id // empty' <<<"$INPUT")
[[ -n "$sid" && -x "$Q" ]] || exit 0

q() { "$Q" --session "$sid" "$@"; }
open=$(q count 2>/dev/null || echo 0)
[[ "$open" =~ ^[0-9]+$ ]] || open=0

emit_context() { # $1 = hook event name, $2 = context text
  jq -nc --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
}

case "$event" in
  SessionStart)
    "$Q" prune >/dev/null 2>&1 || true
    ctx="Parked-question tracker is active for this session. When you need an answer from the user, park it instead of writing an 'input needed' banner yourself (the Stop hook shows the flag deterministically): \`$Q --session $sid add --title \"<short title>\" --context \"<why it matters>\" [--option \"<opt>\"]... [--recommend \"<pick>\"]\`. Keep working on anything the question does not block. When the user answers a parked question in chat, record it: \`$Q --session $sid answer <id>\`. See the park-question skill for details."
    if ((open > 0)); then
      ctx+=$'\n\nOpen parked questions:\n'"$(q list)"
    fi
    emit_context SessionStart "$ctx"
    ;;
  UserPromptSubmit)
    ((open > 0)) || exit 0
    ids=$(q list --json | jq -r 'map("Q\(.id)") | join(", ")')
    emit_context UserPromptSubmit "Open parked questions: ${ids}. If this prompt answers any of them, record it: \`$Q --session $sid answer <id>\`."
    ;;
  Stop)
    ((open > 0)) || exit 0
    bg=$(jq -r '(.background_tasks // []) | length' <<<"$INPUT" 2>/dev/null || echo 0)
    [[ "$bg" =~ ^[0-9]+$ ]] || bg=0
    if ((bg > 0)); then
      jq -nc --arg m "⏳ ${open} parked question(s), still working" '{systemMessage: $m}'
    else
      jq -nc --arg m "🛑 INPUT NEEDED (${open}) · /questions:list" '{systemMessage: $m}'
    fi
    ;;
esac
exit 0
