#!/usr/bin/env bash
# test-inbox.sh — utils/inbox state tracking, dedupe, and concurrency.
#
# Usage: bash tests/inbox/test-inbox.sh [filter]

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
skip_filter() { [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; }

# q <args...>: run inbox; sets OUT (stdout), ERR (stderr), CODE.
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

reset() { rm -rf "$INBOX_STATE_DIR"; }

echo "── basics ──"
reset
q --session s1 count
check "count with no state file is 0" "$([[ "$OUT" == "0" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
check "count creates no file" "$([[ ! -e "$INBOX_STATE_DIR" ]] && echo 0 || echo 1)"
q --session s1 list
check "list on empty prints nothing" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)"
check "list creates no file" "$([[ ! -e "$INBOX_STATE_DIR" ]] && echo 0 || echo 1)"
q --session s1 add question --title "Pick database engine" --context "ctx" --option pg --option sqlite --recommend pg
check "add prints Q1 added" "$([[ "$OUT" == "Q1 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT err=$ERR"
q --session s1 add question --title "Rename the widget module"
check "second add is Q2" "$([[ "$OUT" == "Q2 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 count
check "count is 2" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 list
check "list one line per question" "$([[ "$OUT" == $'Q1 Pick database engine\nQ2 Rename the widget module' ]] && echo 0 || echo 1)" "out=$OUT"

echo "── monotonic ids ──"
reset
q --session s1 add question --title "alpha one"
q --session s1 add question --title "beta two"
q --session s1 answer Q2
check "answer prints Q2 answered" "$([[ "$OUT" == "Q2 answered" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 add question --title "gamma three"
check "id not reused after answer" "$([[ "$OUT" == "Q3 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 answer Q1
q --session s1 answer Q3
q --session s1 add question --title "delta four"
check "id keeps increasing when empty" "$([[ "$OUT" == "Q4 added" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── dedupe ──"
reset
q --session s1 add question --title "Should we use Postgres for storage?"
q --session s1 add question --title "Use postgres for the storage"
check "similar title exits 3" "$([[ $CODE -eq 3 ]] && echo 0 || echo 1)" "code=$CODE"
check "similar title message names Q1" "$([[ "$ERR" == "similar to Q1: Should we use Postgres for storage? — use 'update Q1' or pass --new" ]] && echo 0 || echo 1)" "err=$ERR"
q --session s1 count
check "dedupe hit adds nothing" "$([[ "$OUT" == "1" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 add question --title "Pick a logging framework"
check "dedupe miss adds" "$([[ "$OUT" == "Q2 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
q --session s1 add question --new --title "Use postgres for the storage"
check "--new overrides dedupe" "$([[ "$OUT" == "Q3 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
q --session s1 add question
check "add without title exits 2" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"

echo "── update ──"
reset
q --session s1 add question --title "Original title" --context old --option a --option b --recommend a
q --session s1 update Q1 --title "New title" --option x
q --session s1 list --kind question --json
ok=1
jq -e '.[0].title == "New title" and .[0].options == ["x"] and .[0].context == "old" and .[0].recommendation == "a"' <<<"$OUT" >/dev/null && ok=0
check "update replaces provided fields only" "$ok" "out=$OUT"
q --session s1 update Q99 --title zzz
check "update unknown id exits 1" "$([[ $CODE -eq 1 ]] && echo 0 || echo 1)" "code=$CODE"
q --session s1 answer Q99
check "answer unknown id exits 1" "$([[ $CODE -eq 1 && -n "$ERR" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session s1 answer Q1 --note "done"
check "answer accepts --note" "$([[ "$OUT" == "Q1 answered" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── list formats ──"
reset
q --session s1 add question --title "Pick engine" --context "Need persistence" --option pg --option sqlite --recommend pg
q --session s1 list --full
want=$'Q1 Pick engine\n  context: Need persistence\n  options:\n    - pg\n    - sqlite\n  recommendation: pg'
check "list --full output" "$([[ "$OUT" == "$want" ]] && echo 0 || echo 1)" "out=$OUT"
q --session s1 list --kind question --json
ok=1
jq -e 'type == "array" and length == 1 and .[0].id == 1 and (.[0].added | type == "number") and .[0].options == ["pg","sqlite"]' <<<"$OUT" >/dev/null && ok=0
check "list --json is questions array" "$ok" "out=$OUT"

echo "── sessions ──"
reset
q --session s1 add question --title "only in s1"
q --session s2 count
check "sessions are isolated" "$([[ "$OUT" == "0" ]] && echo 0 || echo 1)" "out=$OUT"
q count
check "missing session exits 2" "$([[ $CODE -eq 2 && "$ERR" == *session* ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
out=$(INBOX_SESSION=s1 bash "$Q" count)
check "INBOX_SESSION env fallback" "$([[ "$out" == "1" ]] && echo 0 || echo 1)" "out=$out"
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
mkdir -p "$INBOX_STATE_DIR"
touch -d '10 days ago' "$INBOX_STATE_DIR/old.json" "$INBOX_STATE_DIR/old.lock"
touch "$INBOX_STATE_DIR/fresh.json" "$INBOX_STATE_DIR/fresh.lock"
q prune
check "prune prints nothing" "$([[ -z "$OUT" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE"
check "prune removes old files" "$([[ ! -e "$INBOX_STATE_DIR/old.json" && ! -e "$INBOX_STATE_DIR/old.lock" ]] && echo 0 || echo 1)"
check "prune keeps fresh files" "$([[ -e "$INBOX_STATE_DIR/fresh.json" && -e "$INBOX_STATE_DIR/fresh.lock" ]] && echo 0 || echo 1)"
touch -d '3 days ago' "$INBOX_STATE_DIR/mid.json"
q prune --days 2
check "prune --days N honors threshold" "$([[ ! -e "$INBOX_STATE_DIR/mid.json" && -e "$INBOX_STATE_DIR/fresh.json" ]] && echo 0 || echo 1)"

echo "── concurrency ──"
reset
bash "$Q" --session c1 add question --title "alpha apple" >"$TMP/c1.out" 2>&1 &
p1=$!
bash "$Q" --session c1 add question --title "zebra yak" >"$TMP/c2.out" 2>&1 &
p2=$!
wait "$p1" "$p2" || true
q --session c1 count
check "two concurrent adds both land" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "count=$OUT"
q --session c1 list --kind question --json
check "concurrent adds have distinct ids" "$(jq -e '[.[].id] | unique | length == 2' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"

echo "── decisions ──"
reset
q --session d1 add decision --title "Use sqlite for cache" --context "no infra" --option pg --option redis --chosen sqlite
check "add decision prints D1 added" "$([[ "$OUT" == "D1 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT err=$ERR"
q --session d1 add decision --title "Name the module widget"
check "second decision is D2" "$([[ "$OUT" == "D2 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 list
check "list shows decisions" "$([[ "$OUT" == $'D1 Use sqlite for cache\nD2 Name the module widget' ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 list --full --kind decision
want=$'D1 Use sqlite for cache\n  context: no infra\n  options:\n    - pg\n    - redis\n  chosen: sqlite\nD2 Name the module widget'
check "list --full shows chosen" "$([[ "$OUT" == "$want" ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 count
check "count total includes decisions" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 count --kind question
check "count --kind question is 0" "$([[ "$OUT" == "0" ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 count --kind decision
check "count --kind decision is 2" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session d1 add decision --title "Another thing" --recommend x
check "add decision rejects --recommend" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session d1 add question --title "Another thing" --chosen x
check "add question rejects --chosen" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session d1 add bogus --title x
check "add unknown kind exits 2" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session d1 resolve d1 --note ok
check "resolve accepts lowercase d1 and --note" "$([[ "$OUT" == "D1 resolved" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT err=$ERR"
q --session d1 add decision --title "third thing"
check "decision id not reused" "$([[ "$OUT" == "D3 added" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── independent counters ──"
reset
q --session k1 add question --title "alpha one"
q --session k1 add decision --title "beta two"
q --session k1 add question --title "gamma three"
q --session k1 add decision --title "delta four"
check "Q and D counters independent" "$([[ "$OUT" == "D2 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 answer Q2
q --session k1 resolve D2
q --session k1 add question --title "epsilon five"
check "question counter monotonic after answer" "$([[ "$OUT" == "Q3 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 add decision --title "zeta six"
check "decision counter monotonic after resolve" "$([[ "$OUT" == "D3 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 list
check "list shows questions before decisions" "$([[ "$OUT" == $'Q1 alpha one\nQ3 epsilon five\nD1 beta two\nD3 zeta six' ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 list --kind question
check "list --kind question only" "$([[ "$OUT" == $'Q1 alpha one\nQ3 epsilon five' ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 list --kind decision
check "list --kind decision only" "$([[ "$OUT" == $'D1 beta two\nD3 zeta six' ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 list --kind bogus
check "list bad kind exits 2" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session k1 count
check "count without --kind is total" "$([[ "$OUT" == "4" ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 count --kind question
check "count --kind question" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session k1 count --kind decision
check "count --kind decision" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── dedupe per kind ──"
reset
q --session p1 add question --title "Should we use Postgres for storage?"
q --session p1 add decision --title "Use postgres for the storage"
check "decision similar to open question is not rejected" "$([[ "$OUT" == "D1 added" && $CODE -eq 0 ]] && echo 0 || echo 1)" "out=$OUT code=$CODE err=$ERR"
q --session p1 add decision --title "Use the postgres storage"
check "similar decision exits 3" "$([[ $CODE -eq 3 ]] && echo 0 || echo 1)" "code=$CODE"
check "similar decision message names D1" "$([[ "$ERR" == "similar to D1: Use postgres for the storage — use 'update D1' or pass --new" ]] && echo 0 || echo 1)" "err=$ERR"
q --session p1 add decision --new --title "Use the postgres storage"
check "decision --new overrides dedupe" "$([[ "$OUT" == "D2 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session p1 add question --title "Use postgres storage"
check "question still dedupes against questions" "$([[ $CODE -eq 3 && "$ERR" == "similar to Q1:"* ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"

echo "── wrong-kind errors ──"
reset
q --session w1 add question --title "a question"
q --session w1 add decision --title "a decision"
q --session w1 answer D1
check "answer D1 exits 1 with hint" "$([[ $CODE -eq 1 && "$ERR" == *"D1 is a decision; use 'resolve D1'" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session w1 resolve Q1
check "resolve Q1 exits 1 with hint" "$([[ $CODE -eq 1 && "$ERR" == *"Q1 is a question; use 'answer Q1'" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session w1 count
check "wrong-kind errors remove nothing" "$([[ "$OUT" == "2" ]] && echo 0 || echo 1)" "out=$OUT"
q --session w1 resolve D9
check "resolve unknown id exits 1" "$([[ $CODE -eq 1 && -n "$ERR" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session w1 answer 1
check "bare numeric id rejected (exit 2)" "$([[ $CODE -eq 2 ]] && echo 0 || echo 1)" "code=$CODE"
q --session w1 answer Q1
check "answer Q1 works" "$([[ "$OUT" == "Q1 answered" ]] && echo 0 || echo 1)" "out=$OUT"

echo "── update kinds ──"
reset
q --session u1 add question --title "Q title" --recommend a
q --session u1 add decision --title "D title" --chosen x --option y
q --session u1 update D1 --title "D new" --chosen z --option w
check "update decision prints D1 updated" "$([[ "$OUT" == "D1 updated" ]] && echo 0 || echo 1)" "out=$OUT err=$ERR"
q --session u1 list --kind decision --json
check "update decision applies fields" "$(jq -e '.[0].title == "D new" and .[0].chosen == "z" and .[0].options == ["w"]' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"
q --session u1 update q1 --recommend b
check "update question (lowercase q1) --recommend" "$([[ "$OUT" == "Q1 updated" ]] && echo 0 || echo 1)" "out=$OUT"
q --session u1 list --kind question --json
check "question recommendation updated" "$(jq -e '.[0].recommendation == "b"' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"
q --session u1 update D1 --recommend nope
check "update decision --recommend exits 1" "$([[ $CODE -eq 1 && -n "$ERR" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session u1 update Q1 --chosen nope
check "update question --chosen exits 1" "$([[ $CODE -eq 1 && -n "$ERR" ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"
q --session u1 update D9 --title zzz
check "update unknown decision exits 1" "$([[ $CODE -eq 1 && "$ERR" == *D9* ]] && echo 0 || echo 1)" "code=$CODE err=$ERR"

echo "── list --json shapes ──"
reset
q --session j1 add question --title "a question"
q --session j1 add decision --title "a decision" --chosen c
q --session j1 list --json
check "list --json without --kind is object of both" "$(jq -e 'keys == ["decisions","questions"] and (.questions | length == 1) and (.decisions | length == 1) and .decisions[0].chosen == "c"' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"
q --session j1 list --kind decision --json
check "list --kind decision --json is array" "$(jq -e 'type == "array" and length == 1 and .[0].id == 1' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"
q --session j1 list --kind question --json
check "list --kind question --json is array" "$(jq -e 'type == "array" and length == 1' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"

echo "── old-shape state ──"
reset
mkdir -p "$INBOX_STATE_DIR"
echo '{"next_id":3,"questions":[{"id":2,"title":"legacy question","context":"","options":[],"recommendation":"","added":1}]}' >"$INBOX_STATE_DIR/old1.json"
q --session old1 list
check "old-shape state readable" "$([[ "$OUT" == "Q2 legacy question" ]] && echo 0 || echo 1)" "out=$OUT"
q --session old1 count --kind decision
check "old-shape state has 0 decisions" "$([[ "$OUT" == "0" ]] && echo 0 || echo 1)" "out=$OUT"
q --session old1 add decision --title "first decision"
check "decision added to old-shape state starts at D1" "$([[ "$OUT" == "D1 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session old1 add question --title "another question entirely"
check "question counter preserved from old state" "$([[ "$OUT" == "Q3 added" ]] && echo 0 || echo 1)" "out=$OUT"
q --session old1 list --json
check "old questions kept after adding decisions" "$(jq -e '(.questions | map(.id)) == [2,3] and (.decisions | length == 1)' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"
check "state file now has decision counter" "$(jq -e '.next_decision_id == 2' "$INBOX_STATE_DIR/old1.json" >/dev/null && echo 0 || echo 1)"

echo "── concurrency (mixed kinds) ──"
reset
bash "$Q" --session c2 add question --title "alpha apple" >"$TMP/m1.out" 2>&1 &
p1=$!
bash "$Q" --session c2 add decision --title "zebra yak" >"$TMP/m2.out" 2>&1 &
p2=$!
bash "$Q" --session c2 add decision --title "mango kiwi" >"$TMP/m3.out" 2>&1 &
p3=$!
bash "$Q" --session c2 add question --title "plum cherry" >"$TMP/m4.out" 2>&1 &
p4=$!
wait "$p1" "$p2" "$p3" "$p4" || true
q --session c2 count
check "four concurrent mixed adds all land" "$([[ "$OUT" == "4" ]] && echo 0 || echo 1)" "count=$OUT"
q --session c2 list --json
check "mixed concurrent adds have distinct ids per kind" "$(jq -e '([.questions[].id] | unique | length == 2) and ([.decisions[].id] | unique | length == 2)' <<<"$OUT" >/dev/null && echo 0 || echo 1)" "out=$OUT"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
