#!/usr/bin/env bash
# test-generated-drift.sh — the drift guards around generated trees.
#
# Covers .claude/hooks/check-generated-drift.sh (blocks commits while a
# generated tree is stale) and utils/regen-generated.sh (ordering + --check
# propagation). Both run against a sandbox repo with stub generators, so the
# real plugins-* trees and skills-catalog/ are never touched.
#
# Usage: bash tests/ci/test-generated-drift.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$SCRIPT_DIR/.."

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
# check <label> <expected-exit> <actual-exit>
check() {
  if [[ "$2" == "nonzero" && "$3" -ne 0 ]] || [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "expected exit $2, got $3"
  fi
}

# --- sandbox repo with stub generators ------------------------------------------
S="$TMP/repo"
mkdir -p "$S/utils" "$S/.claude/hooks"
cp "$REPO/.claude/hooks/check-generated-drift.sh" "$S/.claude/hooks/"
cp "$REPO/utils/regen-generated.sh" "$S/utils/"
LOG="$TMP/calls.log"
# Each stub records its name + args; STUB_DRIFT=<name> makes that stage fail.
for stage in sync.sh port-session-skills.py skills-catalog.py; do
  cat >"$S/utils/$stage" <<EOF
#!/usr/bin/env bash
echo "$stage \$*" >>"$LOG"
[[ "\${STUB_DRIFT:-}" == "$stage" ]] && exit 1
exit 0
EOF
  chmod +x "$S/utils/$stage"
done
git -C "$S" init -q

# The wrapper invokes the .py stages through python3; shim them as bash stubs.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/python3" <<'EOF'
#!/usr/bin/env bash
exec bash "$@"
EOF
chmod +x "$TMP/bin/python3"
export PATH="$TMP/bin:$PATH"

hook() { # hook <command> — run the hook as Claude Code would, cwd = sandbox
  (cd "$S" && jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$S/.claude/hooks/check-generated-drift.sh")
}

# --- wrapper -------------------------------------------------------------------
: >"$LOG"
RC=0
bash "$S/utils/regen-generated.sh" >/dev/null 2>&1 || RC=$?
check "regen runs clean" 0 "$RC"
order=$(cut -d' ' -f1 "$LOG" | paste -sd, -)
if [[ "$order" == "sync.sh,port-session-skills.py,skills-catalog.py" ]]; then
  pass "regen order is sync -> port -> catalog"
else
  fail "regen order is sync -> port -> catalog" "got $order"
fi
if grep -q -- '--check' "$LOG"; then fail "regen passes no --check" "$(cat "$LOG")"; else pass "regen passes no --check"; fi

: >"$LOG"
RC=0
bash "$S/utils/regen-generated.sh" --check >/dev/null 2>&1 || RC=$?
check "--check clean exits 0" 0 "$RC"
if [[ $(grep -c -- '--check' "$LOG") -eq 3 ]]; then pass "--check reaches all three stages"; else fail "--check reaches all three stages" "$(cat "$LOG")"; fi

for stage in sync.sh port-session-skills.py skills-catalog.py; do
  : >"$LOG"
  RC=0
  STUB_DRIFT="$stage" bash "$S/utils/regen-generated.sh" --check >/dev/null 2>&1 || RC=$?
  check "--check fails when $stage drifts" nonzero "$RC"
  if [[ $(wc -l <"$LOG") -eq 3 ]]; then pass "--check still runs every stage after $stage drifts"; else fail "--check still runs every stage after $stage drifts" "$(cat "$LOG")"; fi
done

RC=0
bash "$S/utils/regen-generated.sh" --bogus >/dev/null 2>&1 || RC=$?
check "unknown flag is rejected" nonzero "$RC"

# --- hook ----------------------------------------------------------------------
RC=0
hook "git commit -m x" >/dev/null 2>&1 || RC=$?
check "hook allows a commit when nothing drifts" 0 "$RC"

RC=0
STUB_DRIFT=skills-catalog.py hook "git add a && git commit -m x" >/dev/null 2>"$TMP/err" || RC=$?
check "hook blocks a chained commit on drift (exit 2)" 2 "$RC"
if grep -q "regen-generated.sh" "$TMP/err"; then pass "hook message names the fix command"; else fail "hook message names the fix command" "$(cat "$TMP/err")"; fi

RC=0
STUB_DRIFT=sync.sh hook "git -C . commit -m x" >/dev/null 2>&1 || RC=$?
check "hook blocks 'git -C <dir> commit' on drift" 2 "$RC"

for form in "git --no-pager commit -m x" "git -p commit -m x" "git --git-dir=.git commit -m x" "git -c user.name=a commit -m x"; do
  RC=0
  STUB_DRIFT=sync.sh hook "$form" >/dev/null 2>&1 || RC=$?
  check "hook blocks on drift: $form" 2 "$RC"
done

# regen mode stops at the first failing stage (later stages read its output)
: >"$LOG"
RC=0
STUB_DRIFT=sync.sh bash "$S/utils/regen-generated.sh" >/dev/null 2>&1 || RC=$?
check "regen mode fails when a stage fails" nonzero "$RC"
if [[ $(wc -l <"$LOG") -eq 1 ]]; then pass "regen mode stops after the failing stage"; else fail "regen mode stops after the failing stage" "$(cat "$LOG")"; fi

RC=0
STUB_DRIFT=sync.sh hook "git status" >/dev/null 2>&1 || RC=$?
check "hook ignores non-commit git commands" 0 "$RC"

RC=0
STUB_DRIFT=sync.sh hook "echo git-commit-notes" >/dev/null 2>&1 || RC=$?
check "hook ignores a lookalike string" 0 "$RC"

RC=0
(cd "$TMP" && jq -n '{tool_input:{command:"git commit -m x"}}' | bash "$S/.claude/hooks/check-generated-drift.sh") >/dev/null 2>&1 || RC=$?
check "hook is a no-op outside a repo with the wrapper" 0 "$RC"

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
