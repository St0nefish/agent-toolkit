#!/usr/bin/env bash
# test-approver-sandbox.sh — approver-sandbox without a real OpenCode: a stub
# `opencode` on PATH emits canned run JSON, and APPROVER_AUDIT_LOG points at a
# fixture log so the per-run session filtering can be checked.
# The checks below intentionally read $? right after a [[ ]] condition.
# shellcheck disable=SC2319
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOL="$REPO/plugins-opencode/approver/scripts/approver-sandbox"

PASS=0
FAIL=0
pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "  ✗ $1  ($2)"
  FAIL=$((FAIL + 1))
}
check() { # label, condition-exit-code, detail
  if [[ "$2" == 0 ]]; then pass "$1"; else fail "$1" "${3:-}"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/approver-sandbox-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK"

# Stub opencode: records its cwd and PWD, emits one session with a tool call and text.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == session ]]; then echo "{\"stub\":\"$2 $*\"}"; exit 0; fi
printf '%s\n' "$PWD" >"$STUB_RECORD"
printf '%s\n' "$*" >>"$STUB_RECORD"
printf '{"type":"tool_use","sessionID":"ses_stub1","part":{"type":"tool","tool":"shell","state":{"status":"completed","input":{"command":"ls"}}}}\n'
printf '{"type":"text","sessionID":"ses_stub1","part":{"type":"text","text":"all done"}}\n'
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$WORK/bin/opencode"
export PATH="$WORK/bin:$PATH"
export STUB_RECORD="$WORK/stub-record"

# Fixture audit log: two sessions interleaved, only ses_stub1 belongs to the run.
export APPROVER_AUDIT_LOG="$WORK/audit.jsonl"
cat >"$APPROVER_AUDIT_LOG" <<'EOF'
{"sessionID":"ses_other","action":"shell","resources":["rm x"],"source":"model","verdict":"ask","latencyMs":5}
{"sessionID":"ses_stub1","action":"shell","resources":["ls"],"source":"prefilter-allow","verdict":"allow","latencyMs":0}
{"sessionID":"ses_stub1","action":"shell","resources":["echo hi > a"],"source":"model","verdict":"allow","latencyMs":600,"phases":{"judgeMs":590},"model":"p/m#nothink","reason":"requested"}
EOF
export OPENCODE_CONFIG="$WORK/opencode.json"
cat >"$OPENCODE_CONFIG" <<'EOF'
{
  // a comment
  "plugins": [
    {"package": "/x/plugins-opencode/approver", "options": {"model": "p/m#nothink", "shadow": true}}
  ]
}
EOF

# --- create ---------------------------------------------------------------------------
A=$("$TOOL" create)
B=$("$TOOL" create)
[[ -d "$A/repo/.git" && -f "$A/state/.approver-sandbox" ]]
check "create makes a git repo with a marker" $?
[[ "$A" != "$B" && "$(basename "$A")" == approver-sandbox.* ]]
check "sandbox paths are randomized per create" $?
git -C "$A/repo" log --oneline | grep -q init
check "sandbox repo has an initial commit" $?

# --- run ------------------------------------------------------------------------------
OUT=$("$TOOL" run "$A" --prompt "hello there" --model p/agent 2>"$WORK/run.err")
[[ "$OUT" == "run 001: exit 0, 2 approver decision(s), session(s): ses_stub1 " ]]
check "run reports exit, filtered decision count and session" $? "$OUT"
[[ "$(head -1 "$STUB_RECORD")" == "$A/repo" ]]
check "agent runs with cwd/PWD = the sandbox repo" $? "$(head -1 "$STUB_RECORD")"
grep -q -- "--standalone" "$STUB_RECORD" && grep -q -- "--archived" "$STUB_RECORD" && grep -q -- "--model p/agent" "$STUB_RECORD"
check "run passes --standalone --archived --model" $?
grep -q "approver: SHADOW" "$WORK/run.err"
check "run prints the approver mode (shadow) from the OpenCode config" $?

# --- log / output / status / sessions / export --------------------------------------------
LOG=$("$TOOL" log "$A")
[[ "$LOG" == *"echo hi > a"* && "$LOG" != *"rm x"* ]]
check "log shows this run's decisions only (filtered by session id)" $?
[[ "$("$TOOL" log "$A" last --json | wc -l | tr -d ' ')" == 2 ]]
check "log --json emits the raw lines" $?
OUTPUT=$("$TOOL" output "$A")
[[ "$OUTPUT" == *"tool  shell [completed]"* && "$OUTPUT" == *"text  all done"* ]]
check "output shows tool calls and the final text" $? "$OUTPUT"
"$TOOL" status "$A" | grep -q "run 001"
check "status lists the run" $?
[[ "$("$TOOL" sessions "$A")" == ses_stub1 ]]
check "sessions lists recorded session ids" $?
"$TOOL" export "$A" | grep -q "ses_stub1"
check "export resolves 'last' to the recorded session" $?

# --- second run, session targeting, timeout exit ------------------------------------------
"$TOOL" run "$A" --prompt "again" --session ses_stub1 >/dev/null 2>&1
grep -q -- "--session ses_stub1" "$STUB_RECORD"
check "run --session targets an existing session" $?
[[ "$(find "$A/state/runs" -name 'run-*.meta.json' | wc -l | tr -d ' ')" == 2 ]]
check "second run gets its own record" $?
STUB_EXIT=7 "$TOOL" run "$A" --prompt x 2>/dev/null | grep -q "exit 7"
check "non-zero agent exit is reported" $?
"$TOOL" run "$A" 2>/dev/null
check_rc=$?
[[ "$check_rc" != 0 ]]
check "run without a prompt is an error" $?

# --- guards --------------------------------------------------------------------------------
mkdir -p "$WORK/not-a-sandbox/repo"
"$TOOL" destroy "$WORK/not-a-sandbox" 2>/dev/null
[[ $? != 0 && -d "$WORK/not-a-sandbox" ]]
check "destroy refuses a directory that is not a sandbox" $?
mkdir -p "$WORK/approver-sandbox.fake/repo" "$WORK/approver-sandbox.fake/state"
"$TOOL" destroy "$WORK/approver-sandbox.fake" 2>/dev/null
[[ $? != 0 && -d "$WORK/approver-sandbox.fake" ]]
check "destroy refuses a look-alike without the marker" $?
"$TOOL" destroy "$HOME" 2>/dev/null
[[ $? != 0 && -d "$HOME" ]]
check "destroy refuses \$HOME" $?
"$TOOL" destroy "$B" >/dev/null && [[ ! -e "$B" ]]
check "destroy removes a real sandbox" $?
"$TOOL" destroy --all >/dev/null
[[ ! -e "$A" && -d "$WORK/not-a-sandbox" ]]
check "destroy --all removes sandboxes and nothing else" $?

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" == 0 ]]
