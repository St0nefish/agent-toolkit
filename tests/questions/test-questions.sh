#!/usr/bin/env bash
# test-questions.sh — utils/questions state tracking, dedupe, and concurrency.
#
# Usage: bash tests/questions/test-questions.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Q="$SCRIPT_DIR/../../utils/questions"

PASS=0
FAIL=0
FILTER="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export QUESTIONS_STATE_DIR="$TMP/state"
unset QUESTIONS_SESSION

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
skip_filter() { [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; }

# q <args...>: run questions; sets OUT (stdout), ERR (stderr), CODE.
q() {
  CODE=0
  OUT=$(bash "$Q" "$@" 2>"$TMP/stderr") || CODE=$?
  ERR=$(cat "$TMP/stderr")
}

# check <label> <condition-result 0|1> [detail]
check() {
  if skip_filter "$1"; then return; fi
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "${3:-}"; fi
}

reset() { rm -rf "$QUESTIONS_STATE_DIR"; }

echo "── basics ──"
reset
q --session s1 count
check "count with no state file is 0" "$([[ "$OUT" == "0" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
check "count creates no file" "$([[ ! -e "$QUESTIONS_STATE_DIR" ]] && echo 0 || echo 1)"
q --session s1 list
check "list on empty prints nothing" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)"
check "list creates no file" "$([[ ! -e "$QUESTIONS_STATE_DIR" ]] && echo 0 || echo 1)"
q --session s1 add --title "Pick database engine" --context "ctx" --option pg --option sqlite --recommend pg
check "add prints Q1 added" "$([[ "$OUT" == "Q1 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT err=$ERR"
q --session s1 add --title "Rename the widget module"
check "second add is Q2" "$([[ "$OUT" == "Q2 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 count
check "count is 2" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 list
check "list one line per question" "$([[ "$OUT" == $'Q1 Pick database engine\nQ2 Rename the widget module' ]] && echo 0 || echo 1)" "out=$OUT"

echo "── monotonic ids ──"
reset
q --session s1 add --title "alpha one"
q --session s1 add --title "beta two"
q --session s1 answer 2
check "answer prints Q2 answered" "$([[ "$OUT" == "Q2 answered" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 add --title "gamma three"
check "id not reused after answer" "$([[ "$OUT" == "Q3 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 answer 1
q --session s1 answer 3
q --session s1 add --title "delta four"
check "id keeps increasing when empty" "$([[ "$OUT" == "Q4 added" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── dedupe ──"
reset
q --session s1 add --title "Should we use Postgres for storage?"
q --session s1 add --title "Use postgres for the storage"
check "similar title exits 3" "$([[ $CODE -eq 3 ]] && echo 0 || echo 1)" "code=$CODE"
check "similar title message names Q1" "$([[ "$ERR" == "similar to Q1: Should we use Postgres for storage? — use 'update 1' or pass --new" ]] && echo 0 || echo 1)" "err=$ERR"
q --session s1 count
check "dedupe hit adds nothing" "$([[ "$OUT" == "1" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 add --title "Pick a logging framework"
check "dedupe miss adds" "$([[ "$OUT" == "Q2 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
q --session s1 add --new --title "Use postgres for the storage"
check "--new overrides dedupe" "$([[ "$OUT" == "Q3 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
q --session s1 add
check "add without title exits 2" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"

echo "── update ──"
reset
q --session s1 add --title "Original title" --context old --option a --option b --recommend a
q --session s1 update 1 --title "New title" --option x
q --session s1 list --json
ok=1
jq -e '.[0].title == "New title" and .[0].options == ["x"] and .[0].context == "old" and .[0].recommendation == "a"' <<<"$OUT" >/dev/null && ok=0
check "update replaces provided fields only" "$ok" "out=$OUT"
q --session s1 update 99 --title zzz
check "update unknown id exits 1" "$([[ $CODE -eq 1 ]] && echo 0 || echo 1)" "code=$CODE"
q --session s1 answer 99
check "answer unknown id exits 1" "$([[ $CODE -eq 1 && -n "$ERR" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session s1 answer 1 --note "done"
check "answer accepts --note" "$([[ "$OUT" == "Q1 answered" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── list formats ──"
reset
q --session s1 add --title "Pick engine" --context "Need persistence" --option pg --option sqlite --recommend pg
q --session s1 list --full
want=$'Q1 Pick engine\n  context: Need persistence\n  options:\n    - pg\n    - sqlite\n  recommendation: pg'
check "list --full output" "$([[ "$OUT" == "$want" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 list --json
ok=1
jq -e 'type == "array" and length == 1 and .[0].id == 1 and (.[0].added | type == "number") and .[0].options == ["pg","sqlite"]' <<<"$OUT" >/dev/null && ok=0
check "list --json is questions array" "$ok" "out=$OUT"

echo "── sessions ──"
reset
q --session s1 add --title "only in s1"
q --session s2 count
check "sessions are isolated" "$([[ "$OUT" == "0" ]] && echo 0 || echo 1)" "out=$OUT"
q count
check "missing session exits 2" "$([[ $CODE -eq 2 && "$ERR" == *session* ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
out=$(QUESTIONS_SESSION=s1 bash "$Q" count)
check "QUESTIONS_SESSION env fallback" "$([[ "$out" == "1" ]] && echo 0 || echo 1)" "out=$out"
q --session '../evil' count
check "path traversal session rejected" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session 'a/b' count
check "slash in session rejected" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session '..' count
check "dotdot session rejected" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"

echo "── usage ──"
q bogus
check "unknown command exits 2 with usage on stderr" "$([[ $CODE -eq 2 && "$ERR" == *Usage* ]] && echo 0 || echo 1)" "code=$CODE"
q --help
check "--help exits 0" "$([[ $CODE -eq 0 && "$OUT" == *Usage* ]] && echo 0 || echo 1)"

echo "── prune ──"
reset
mkdir -p "$QUESTIONS_STATE_DIR"
touch -d '10 days ago' "$QUESTIONS_STATE_DIR/old.json" "$QUESTIONS_STATE_DIR/old.lock"
touch "$QUESTIONS_STATE_DIR/fresh.json" "$QUESTIONS_STATE_DIR/fresh.lock"
q prune
check "prune prints nothing" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
check "prune removes old files" "$([[ ! -e "$QUESTIONS_STATE_DIR/old.json" && ! -e "$QUESTIONS_STATE_DIR/old.lock" ]] && echo 0 || echo 1)"
check "prune keeps fresh files" "$([[ -e "$QUESTIONS_STATE_DIR/fresh.json" && -e "$QUESTIONS_STATE_DIR/fresh.lock" ]] && echo 0 || echo 1)"
touch -d '3 days ago' "$QUESTIONS_STATE_DIR/mid.json"
q prune --days 2
check "prune --days N honors threshold" "$([[ ! -e "$QUESTIONS_STATE_DIR/mid.json" && -e "$QUESTIONS_STATE_DIR/fresh.json" ]] && echo 0 || echo 1)"

echo "── concurrency ──"
reset
bash "$Q" --session c1 add --title "alpha apple" >"$TMP/c1.out" 2>&1 &
p1=$!
bash "$Q" --session c1 add --title "zebra yak" >"$TMP/c2.out" 2>&1 &
p2=$!
wait "$p1" "$p2" || true
q --session c1 count
check "two concurrent adds both land" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "count=$OUT"
q --session c1 list --json
check "concurrent adds have distinct ids" "$(jq -e '[.[].id] | unique | length == 2' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
