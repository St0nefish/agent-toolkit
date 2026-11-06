#!/usr/bin/env bash
# Hook dispatcher for the inbox plugin (SessionStart / UserPromptSubmit / Stop).
# Reads the hook payload on stdin; prints only a JSON object (or nothing) on stdout.
# Only open QUESTIONS drive the flag; decisions and followups never produce Stop/prompt output.
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
nf=$(num "$(q count --kind followup 2>/dev/null || echo 0)")

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
    ctx="Inbox tracker is active for this session. It holds three kinds of items (questions, decisions, followups). Commands:
- add a question (blocks on the user): \`$P add question --title \"<short title>\" --context \"<why it matters>\" [--option \"<opt>\"]... [--recommend \"<pick>\"]\`
- add a decision (you proceeded on a default): \`$P add decision --title \"<short title>\" --context \"<why>\" [--option \"<alternative>\"]... --chosen \"<what you went with>\"\`
- record an answer: \`$P answer Q<n>\`
- resolve a decision: \`$P resolve D<n>\`
- log a followup (work to consider before wrapping up: noticed but out of scope, deferred, docs or tests not done, an issue worth filing): \`$P add followup --title \"<short imperative title>\" [--context \"<why>\"]\`
- mark a followup done: \`$P done F<n>\`

Policy: default to proceeding and avoid being blocked. When a choice is the user's, pick the most likely right answer, state the assumption, keep going, and record a decision (what you chose, alternatives, why). Park a question only when a guess would be unsafe (destructive, hard to reverse, outward-facing, spends money or credentials) or information is genuinely missing, and hold only the affected work while continuing everything else. Record only key decisions (approach, architecture, naming, scope, assumptions the user would want a say in), not trivial edits. Never write an 'INPUT NEEDED' banner; the hooks show the flag. Followups are quiet like decisions and never raise the input-needed flag; log them as you notice them and close them with done as you finish. See the park-question, record-decision and record-followup skills.

Writing rule for questions and decisions: --title is the question itself, ending in '?' (under ~70 chars, issue number last); --chosen / --recommend is a short answer phrase (under ~80 chars, answer first, no reasons); each --option is one short alternative; reasons go in --context. Start --recommend with the option letter (a, b, ...). Followup titles are short imperative notes (not questions); put detail in --context."
    if ((nq + nd + nf > 0)); then
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
      full=$(q list --kind question --full)
      hdr="🛑 INPUT NEEDED (${nq}) · /inbox:questions"
      [[ -n "$full" ]] && hdr+=$'\n\n'"$full"
      jq -nc --arg m "$hdr" '{systemMessage: $m}'
    fi
    ;;
esac
exit 0
