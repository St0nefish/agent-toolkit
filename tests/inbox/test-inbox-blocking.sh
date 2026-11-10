#!/usr/bin/env bash
# test-inbox-blocking.sh — the optional `blocking` field on questions:
# default false, --blocking sets it, question-only, backfilled on legacy
# state files, and invisible to the "count questions" contract that
# notify-on-stop depends on.
#
# Usage: bash tests/inbox/test-inbox-blocking.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Q="$SCRIPT_DIR/../../utils/inbox"

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

RC=0
OUT=""
q() {
	RC=0
	OUT=$("$@" 2>&1) || RC=$?
}
t() { # <label> <expect: 0|nonzero> — check $RC from last q
	local label="$1" expect="$2"
	if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then return; fi
	if [[ "$expect" == "0" && $RC -eq 0 ]] || [[ "$expect" == "nonzero" && $RC -ne 0 ]]; then
		pass "$label"
	else
		fail "$label" "exit=$RC out=$OUT"
	fi
}

S=(--session blocktest)

# default: blocking=false
q bash "$Q" "${S[@]}" add question --title "Default question?"
t "add question succeeds" 0
q bash "$Q" "${S[@]}" list --kind question --json
echo "$OUT" | jq -e '.[0].blocking == false' >/dev/null
t "default question has blocking=false" 0

# --blocking sets true
q bash "$Q" "${S[@]}" add question --blocking --title "Hard stop?"
t "add question --blocking succeeds" 0
q bash "$Q" "${S[@]}" list --kind question --json
echo "$OUT" | jq -e '[.[] | select(.blocking == true)] | length == 1' >/dev/null
t "blocking question has blocking=true" 0

# question-only flags
q bash "$Q" "${S[@]}" add decision --blocking --title "A decision"
t "decision --blocking rejected" nonzero
q bash "$Q" "${S[@]}" add followup --blocking --title "A followup"
t "followup --blocking rejected" nonzero

# count contract unchanged: counts ALL questions regardless of blocking
q bash "$Q" "${S[@]}" count --kind question
if [[ "$OUT" == "2" ]]; then pass "count --kind question counts both (notify-on-stop contract)"; else fail "count --kind question counts both (notify-on-stop contract)" "got: $OUT"; fi

# legacy state file backfill: hand-write a pre-blocking question
LEG="$TMP/state/legacy.json"
mkdir -p "$TMP/state"
cat >"$LEG" <<'EOF'
{"next_id":2,"questions":[{"id":1,"title":"Old question?","context":"","options":[],"recommendation":"","added":1}]}
EOF
q bash "$Q" --session legacy list --kind question --json
echo "$OUT" | jq -e '.[0].blocking == false' >/dev/null
t "legacy question backfilled with blocking=false" 0

# answer works on legacy state and removes the item
q bash "$Q" --session legacy answer Q1
if [[ $RC -eq 0 ]] && jq -e '.questions | length == 0' "$LEG" >/dev/null; then
	pass "answer on legacy state works"
else
	fail "answer on legacy state works" "exit=$RC state=$(cat "$LEG")"
fi

# json shape: blocking present on every question in combined --json too
q bash "$Q" "${S[@]}" list --json
echo "$OUT" | jq -e '.questions | all(has("blocking"))' >/dev/null
t "combined --json questions all carry blocking" 0

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
