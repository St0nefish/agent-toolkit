#!/usr/bin/env bash
# Hook dispatcher for the inbox plugin (SessionStart / UserPromptSubmit / Stop).
# Reads the hook payload on stdin; prints only a JSON object (or nothing) on stdout.
# Only open QUESTIONS drive the flag; decisions never produce Stop/prompt output.
set -uo pipefail

INPUT=$(cat)
SELF=$(readlink -f "$0")
Q="$(dirname "$SELF")/inbox"

event=$(jq -r '.hook_event_name // empty' <<<"$INPUT")
sid=$(jq -r '.session_id // empty' <<<"$INPUT")
[[ -n "$sid" && -x "$Q" ]] || exit 0

q() { "$Q" --session "$sid" "$@"; }
num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }
nq=$(num "$(q count --kind question 2>/dev/null || echo 0)")
nd=$(num "$(q count --kind decision 2>/dev/null || echo 0)")

emit_context() { # $1 = hook event name, $2 = context text
  jq -nc --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
}

case "$event" in
  SessionStart)
    # A resumed session may be older than the prune window: refresh its own state
    # file first so prune only removes other, abandoned sessions. (Path mirrors
    # utils/inbox; the statusline mod reads the same location.)
    state="${INBOX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-inbox}/$sid.json"
    [[ -f "$state" ]] && touch "$state" 2>/dev/null
    "$Q" prune >/dev/null 2>&1 || true
    P="$(printf '%q' "$Q") --session $sid"
    ctx="Inbox tracker is active for this session. It holds two kinds of items. Commands:
- add a question (blocks on the user): \`$P add question --title \"<short title>\" --context \"<why it matters>\" [--option \"<opt>\"]... [--recommend \"<pick>\"]\`
- add a decision (you proceeded on a default): \`$P add decision --title \"<short title>\" --context \"<why>\" [--option \"<alternative>\"]... --chosen \"<what you went with>\"\`
- record an answer: \`$P answer Q<n>\`
- resolve a decision: \`$P resolve D<n>\`

Policy: default to proceeding and avoid being blocked. When a choice is the user's, pick the most likely right answer, state the assumption, keep going, and record a decision (what you chose, alternatives, why). Park a question only when a guess would be unsafe (destructive, hard to reverse, outward-facing, spends money or credentials) or information is genuinely missing, and hold only the affected work while continuing everything else. Record only key decisions (approach, architecture, naming, scope, assumptions the user would want a say in), not trivial edits. Never write an 'INPUT NEEDED' banner; the hooks show the flag. See the park-question and record-decision skills."
    if ((nq + nd > 0)); then
      ctx+=$'\n\nOpen items:\n'"$(q list)"
    fi
    emit_context SessionStart "$ctx"
    ;;
  UserPromptSubmit)
    ((nq > 0)) || exit 0
    ids=$(q list --kind question --json | jq -r 'map("Q\(.id)") | join(", ")')
    emit_context UserPromptSubmit "Open parked questions: ${ids}. If this prompt answers any of them, record it: \`$(printf '%q' "$Q") --session $sid answer Q<n>\`."
    ;;
  Stop)
    ((nq > 0)) || exit 0
    bg=$(jq -r '(.background_tasks // []) | length' <<<"$INPUT" 2>/dev/null || echo 0)
    bg=$(num "$bg")
    if ((bg > 0)); then
      jq -nc --arg m "⏳ ${nq} parked question(s), still working" '{systemMessage: $m}'
    else
      jq -nc --arg m "🛑 INPUT NEEDED (${nq}) · /inbox:questions" '{systemMessage: $m}'
    fi
    ;;
esac
exit 0
