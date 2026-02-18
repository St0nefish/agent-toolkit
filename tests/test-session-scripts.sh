#!/usr/bin/env bash
# Tests for session scripts (catchup --active-session, handoff)
# Run from repo root: bash tests/test-session-scripts.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CATCHUP="$REPO_DIR/skills/session/bin/catchup"
HANDOFF="$REPO_DIR/skills/session/bin/handoff"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Create isolated temp dir
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
echo "Using TESTDIR=$TESTDIR"

# ============================================================
# catchup tests
# ============================================================

# --- Test: catchup without --active-session omits ACTIVE SESSION section ---
init_catchup_repo() {
    local repo="$TESTDIR/$1"
    mkdir -p "$repo"
    cd "$repo"
    git init -q
    git commit --allow-empty -m "initial" -q
}

init_catchup_repo "catchup-no-flag"
mkdir -p .claude/sessions
cat > .claude/sessions/2026-02-18-test.md << 'EOF'
# Session: Test

**Started:** 2026-02-18T09:00:00-05:00
**Branch:** master
**Status:** active

## Goals
- Test goal
EOF

output=$("$CATCHUP")
if echo "$output" | grep -q '=== ACTIVE SESSION ==='; then
    fail "catchup backward compat" "ACTIVE SESSION should not appear without flag"
else
    pass "catchup backward compat — no ACTIVE SESSION without flag"
fi

if echo "$output" | grep -q '(active)'; then
    pass "catchup backward compat — sessions list still shows (active) marker"
else
    fail "catchup backward compat" "sessions list should show (active) marker"
fi

# --- Test: catchup --active-session includes session content ---
output=$("$CATCHUP" --active-session)
if echo "$output" | grep -q '=== ACTIVE SESSION ==='; then
    pass "catchup --active-session — ACTIVE SESSION section present"
else
    fail "catchup --active-session" "ACTIVE SESSION section missing"
fi

if echo "$output" | grep -q 'file: .claude/sessions/2026-02-18-test.md'; then
    pass "catchup --active-session — file path shown"
else
    fail "catchup --active-session" "file path not shown"
fi

if echo "$output" | grep -q 'Test goal'; then
    pass "catchup --active-session — session content included"
else
    fail "catchup --active-session" "session content not included"
fi

# --- Test: catchup --active-session truncates long files ---
init_catchup_repo "catchup-truncate"
mkdir -p .claude/sessions
{
    echo "# Session: Long"
    echo "**Status:** active"
    for i in $(seq 1 250); do
        echo "line $i"
    done
} > .claude/sessions/2026-02-18-long.md

output=$("$CATCHUP" --active-session)
if echo "$output" | grep -q 'truncated'; then
    pass "catchup --active-session — truncation notice for long file"
else
    fail "catchup --active-session truncation" "no truncation notice"
fi

if echo "$output" | grep -q 'line 250'; then
    pass "catchup --active-session — last line present after truncation"
else
    fail "catchup --active-session truncation" "last line missing"
fi

if echo "$output" | grep -q 'line 1$'; then
    fail "catchup --active-session truncation" "early lines should be truncated"
else
    pass "catchup --active-session — early lines truncated"
fi

# --- Test: catchup --active-session with no active session omits section ---
init_catchup_repo "catchup-no-active"
mkdir -p .claude/sessions
cat > .claude/sessions/2026-02-18-done.md << 'EOF'
# Session: Done
**Status:** completed
EOF

output=$("$CATCHUP" --active-session)
if echo "$output" | grep -q '=== ACTIVE SESSION ==='; then
    fail "catchup --active-session no active" "should not show ACTIVE SESSION when none active"
else
    pass "catchup --active-session — omits section when no active session"
fi

# --- Test: catchup --active-session with directory arg ---
init_catchup_repo "catchup-dir-arg"
mkdir -p .claude/sessions
cat > .claude/sessions/2026-02-18-dir.md << 'EOF'
# Session: Dir Test
**Status:** active
## Goals
- dir test goal
EOF

cd "$TESTDIR"
output=$("$CATCHUP" --active-session "$TESTDIR/catchup-dir-arg")
if echo "$output" | grep -q 'dir test goal'; then
    pass "catchup --active-session with directory arg"
else
    fail "catchup --active-session with dir arg" "content not found"
fi

# ============================================================
# handoff tests
# ============================================================

# --- Test: handoff with no -m flag exits 1 ---
init_catchup_repo "handoff-no-msg"
touch somefile.txt

output=$("$HANDOFF" 2>&1 || true)
"$HANDOFF" 2>/dev/null && {
    fail "handoff no message" "should exit non-zero"
} || {
    rc=$?
    if [[ $rc -eq 1 ]]; then
        pass "handoff — exits 1 without -m flag"
    else
        fail "handoff no message" "expected exit 1, got $rc"
    fi
}

# --- Test: handoff not in git repo exits 2 ---
nogrepo="$TESTDIR/handoff-nogit"
mkdir -p "$nogrepo"
cd "$nogrepo"

"$HANDOFF" -m "test" 2>/dev/null && {
    fail "handoff not git repo" "should exit non-zero"
} || {
    rc=$?
    if [[ $rc -eq 2 ]]; then
        pass "handoff — exits 2 when not a git repo"
    else
        fail "handoff not git repo" "expected exit 2, got $rc"
    fi
}

# --- Test: handoff clean tree exits 3 ---
init_catchup_repo "handoff-clean"

"$HANDOFF" -m "test" 2>/dev/null && {
    fail "handoff clean tree" "should exit non-zero"
} || {
    rc=$?
    if [[ $rc -eq 3 ]]; then
        pass "handoff — exits 3 with clean working tree"
    else
        fail "handoff clean tree" "expected exit 3, got $rc"
    fi
}

# --- Test: handoff creates structured commit ---
init_catchup_repo "handoff-commit"
echo "hello" > feature.txt
echo "world" > util.txt

"$HANDOFF" -m "=== IN PROGRESS ===
- Building feature X

=== NEXT STEPS ===
- Finish tests

=== KEY CONTEXT ===
- Using approach A" 2>/dev/null || true

# Verify commit exists and has structure
commit_msg=$(git log -1 --format=%B)

if echo "$commit_msg" | grep -q '^WIP:'; then
    pass "handoff commit — subject starts with WIP:"
else
    fail "handoff commit structure" "subject should start with WIP:"
fi

if echo "$commit_msg" | grep -q '=== HANDOFF ==='; then
    pass "handoff commit — HANDOFF section present"
else
    fail "handoff commit structure" "HANDOFF section missing"
fi

if echo "$commit_msg" | grep -q '=== IN PROGRESS ==='; then
    pass "handoff commit — IN PROGRESS section present"
else
    fail "handoff commit structure" "IN PROGRESS section missing"
fi

if echo "$commit_msg" | grep -q '=== NEXT STEPS ==='; then
    pass "handoff commit — NEXT STEPS section present"
else
    fail "handoff commit structure" "NEXT STEPS section missing"
fi

if echo "$commit_msg" | grep -q '=== KEY CONTEXT ==='; then
    pass "handoff commit — KEY CONTEXT section present"
else
    fail "handoff commit structure" "KEY CONTEXT section missing"
fi

if echo "$commit_msg" | grep -q '=== FILES IN THIS COMMIT ==='; then
    pass "handoff commit — FILES IN THIS COMMIT section present"
else
    fail "handoff commit structure" "FILES IN THIS COMMIT section missing"
fi

if echo "$commit_msg" | grep -q 'feature.txt'; then
    pass "handoff commit — file list includes feature.txt"
else
    fail "handoff commit structure" "feature.txt not in file list"
fi

if echo "$commit_msg" | grep -q 'Branch:'; then
    pass "handoff commit — Branch metadata present"
else
    fail "handoff commit structure" "Branch metadata missing"
fi

if echo "$commit_msg" | grep -q 'Timestamp:'; then
    pass "handoff commit — Timestamp metadata present"
else
    fail "handoff commit structure" "Timestamp metadata missing"
fi

# --- Test: handoff push failure exits 4 (no remote configured) ---
init_catchup_repo "handoff-no-remote"
echo "test" > file.txt

"$HANDOFF" -m "=== IN PROGRESS ===
- test" 2>/dev/null && {
    fail "handoff push failure" "should exit non-zero when no remote"
} || {
    rc=$?
    if [[ $rc -eq 4 ]]; then
        pass "handoff — exits 4 when push fails (no remote)"
    else
        fail "handoff push failure" "expected exit 4, got $rc"
    fi
}

# Verify commit still exists despite push failure
if git log -1 --format=%s | grep -q '^WIP:'; then
    pass "handoff push failure — commit preserved locally"
else
    fail "handoff push failure" "commit should still exist locally"
fi

# --- Test: handoff truncates long first line ---
init_catchup_repo "handoff-long-subject"
echo "data" > file.txt

long_msg="This is a very long first line that should definitely be truncated because it exceeds seventy-two characters in length
=== IN PROGRESS ===
- stuff"

"$HANDOFF" -m "$long_msg" 2>/dev/null || true

subject=$(git log -1 --format=%s)
if [[ ${#subject} -le 80 ]]; then
    pass "handoff — long subject line truncated"
else
    fail "handoff long subject" "subject too long: ${#subject} chars"
fi

# ============================================================
# catchup handoff detection tests
# ============================================================

# --- Test: catchup detects WIP handoff commit ---
init_catchup_repo "catchup-handoff-detect"
echo "wip content" > feature.txt
git add -A
git commit -q -m "WIP: building feature X

=== HANDOFF ===
Branch: master
Timestamp: 2026-02-18T12:00:00Z
From: laptop

=== IN PROGRESS ===
- Building feature X

=== NEXT STEPS ===
- Finish tests

=== KEY CONTEXT ===
- Using approach A

=== FILES IN THIS COMMIT ===
feature.txt"

output=$("$CATCHUP")
if echo "$output" | grep -q '=== LATEST HANDOFF ==='; then
    pass "catchup handoff detection — LATEST HANDOFF section present"
else
    fail "catchup handoff detection" "LATEST HANDOFF section missing"
fi

if echo "$output" | grep -q 'IN PROGRESS'; then
    pass "catchup handoff detection — handoff body included"
else
    fail "catchup handoff detection" "handoff body not included"
fi

if echo "$output" | grep -q 'From: laptop'; then
    pass "catchup handoff detection — From metadata present"
else
    fail "catchup handoff detection" "From metadata missing"
fi

# --- Test: catchup does NOT show LATEST HANDOFF for normal commits ---
init_catchup_repo "catchup-no-handoff"
echo "normal" > file.txt
git add -A
git commit -q -m "Add normal file"

output=$("$CATCHUP")
if echo "$output" | grep -q '=== LATEST HANDOFF ==='; then
    fail "catchup no false handoff" "LATEST HANDOFF should not appear for normal commits"
else
    pass "catchup — no LATEST HANDOFF for normal commits"
fi

# --- Test: catchup handoff detection works with --active-session ---
init_catchup_repo "catchup-handoff-with-session"
mkdir -p .claude/sessions
cat > .claude/sessions/2026-02-18-handoff.md << 'EOF'
# Session: Handoff Test
**Status:** active
## Goals
- Test handoff with session
EOF

echo "wip" > feature.txt
git add -A
git commit -q -m "WIP: handoff with session

=== HANDOFF ===
Branch: master
Timestamp: 2026-02-18T12:00:00Z
From: desktop

=== IN PROGRESS ===
- Feature work"

output=$("$CATCHUP" --active-session)
if echo "$output" | grep -q '=== LATEST HANDOFF ===' && echo "$output" | grep -q '=== ACTIVE SESSION ==='; then
    pass "catchup — both LATEST HANDOFF and ACTIVE SESSION present"
else
    fail "catchup handoff + session" "expected both sections"
fi

# Verify handoff section has enough for LLM to describe the option
if echo "$output" | grep -q 'From: desktop'; then
    pass "catchup both — handoff From metadata available for LLM"
else
    fail "catchup both" "handoff From metadata missing"
fi

if echo "$output" | grep -q 'Feature work'; then
    pass "catchup both — handoff IN PROGRESS content available"
else
    fail "catchup both" "handoff IN PROGRESS content missing"
fi

# Verify session section has enough for LLM to describe the option
if echo "$output" | grep -q 'file: .claude/sessions/2026-02-18-handoff.md'; then
    pass "catchup both — session file path available"
else
    fail "catchup both" "session file path missing"
fi

if echo "$output" | grep -q 'Test handoff with session'; then
    pass "catchup both — session goals available for LLM"
else
    fail "catchup both" "session goals missing"
fi

# --- Test: both present — with checkpoint in session ---
init_catchup_repo "catchup-handoff-with-checkpoint"
mkdir -p .claude/sessions
cat > .claude/sessions/2026-02-18-checkpoint.md << 'EOF'
# Session: Checkpoint Test
**Status:** active
## Goals
- Build the widget

## Checkpoint 1 — 2026-02-18T10:00:00-05:00

### Completed
- Set up project structure

### In Progress
- Implementing widget renderer

### Next Steps
- Add widget tests

### Key Context
- Using React 19
EOF

echo "wip" > widget.txt
git add -A
git commit -q -m "WIP: widget handoff

=== HANDOFF ===
Branch: master
Timestamp: 2026-02-18T14:00:00Z
From: work-laptop

=== IN PROGRESS ===
- Widget renderer half done

=== NEXT STEPS ===
- Finish renderer and add tests

=== KEY CONTEXT ===
- React 19 concurrent mode

=== FILES IN THIS COMMIT ===
widget.txt"

output=$("$CATCHUP" --active-session)

# Handoff has what LLM needs to describe the option
if echo "$output" | grep -q 'From: work-laptop' && echo "$output" | grep -q 'Widget renderer half done'; then
    pass "catchup both+checkpoint — handoff origin and headline available"
else
    fail "catchup both+checkpoint" "handoff description data missing"
fi

# Session has checkpoint for LLM to describe the alternative
if echo "$output" | grep -q 'Checkpoint 1' && echo "$output" | grep -q 'Add widget tests'; then
    pass "catchup both+checkpoint — checkpoint number and next steps available"
else
    fail "catchup both+checkpoint" "checkpoint data missing"
fi

# Both sections coexist
if echo "$output" | grep -q '=== LATEST HANDOFF ===' && echo "$output" | grep -q '=== ACTIVE SESSION ==='; then
    pass "catchup both+checkpoint — both sections present"
else
    fail "catchup both+checkpoint" "expected both sections"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "================================"
echo "PASSED: $PASS  FAILED: $FAIL"
echo "================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
