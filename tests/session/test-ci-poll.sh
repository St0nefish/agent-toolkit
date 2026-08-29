#!/usr/bin/env bash
# test-ci-poll.sh — Test harness for git-cli run watch.
# Uses mock gh/tea scripts via PATH manipulation to test polling logic.
#
# Usage: bash tests/session/test-ci-poll.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_CLI="$SCRIPT_DIR/../../utils/git-cli"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

MOCK_DIR=""
cleanup() { [[ -n "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"; }
trap cleanup EXIT
MOCK_DIR=$(mktemp -d)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_test() {
  local expected_status="$1" expected_exit="$2" label="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
    --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || exit_code=$?

  local got_status
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')

  if [[ "$got_status" == "$expected_status" && "$exit_code" == "$expected_exit" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected status=%s exit=%s, got status=%s exit=%s)\n" \
      "$label" "$expected_status" "$expected_exit" "$got_status" "$exit_code"
    ((FAIL++)) || true
  fi
}

write_mock_gh() {
  cat >"$MOCK_DIR/gh" <<'MOCK_HEADER'
#!/usr/bin/env bash
# Mock gh script — reads GH_MOCK_MODE from environment
MOCK_HEADER
  cat >>"$MOCK_DIR/gh"
  chmod +x "$MOCK_DIR/gh"
}

# Also mock git so platform detection works (returns github.com remote)
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/test/repo.git" ;;
  *) PATH=${PATH#"${0%/*}":}; exec git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# ---------------------------------------------------------------------------
# Test: pass — run completes with success
# ---------------------------------------------------------------------------

echo "── run watch: CI outcomes ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    # No PR found — force fallback to run list path
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":100,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/100"}]'
    ;;
  run:view)
    echo '{"databaseId":100,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/100","jobs":[{"databaseId":1,"name":"build","conclusion":"success","status":"completed","steps":[{"name":"checkout","conclusion":"success","status":"completed"}]}]}'
    ;;
esac
EOF

run_test "pass" "0" "success → status: pass, exit 0"

# ---------------------------------------------------------------------------
# Test: fail — run completes with failure
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":200,"status":"completed","conclusion":"failure","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/200"}]'
    ;;
  run:view)
    # Check for --log-failed (run logs --failed-only)
    if [[ "${3:-}" == "--log-failed" || "${4:-}" == "--log-failed" ]]; then
      echo "Error in test step"
      exit 0
    fi
    echo '{"databaseId":200,"status":"completed","conclusion":"failure","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/200","jobs":[{"databaseId":1,"name":"lint","conclusion":"failure","status":"completed","steps":[{"name":"run lint","conclusion":"failure","status":"completed"}]},{"databaseId":2,"name":"test","conclusion":"success","status":"completed","steps":[{"name":"run tests","conclusion":"success","status":"completed"}]}]}'
    ;;
esac
EOF

run_test "fail" "0" "failure → status: fail, exit 0"

# Verify failed_jobs field contains the failed job name
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_failed=$(echo "$output" | grep '^failed_jobs:' | sed 's/^failed_jobs: *//')
if [[ "$got_failed" == "lint" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "failure → failed_jobs includes 'lint'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "failure → failed_jobs includes 'lint'" "$got_failed"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: completed with null conclusion (GitHub race condition) → treated as pass
#
# REGRESSION GUARD — this is the exact scenario that caused repeated watch
# timeouts (#53, #57, #58, #60).  GitHub's API can return status:"completed"
# with conclusion:null.  The jq transform in `run list` maps this to
# "success", but if that transform ever breaks again the fallback case
# statement must still exit (not loop).  If this test fails, the watch loop
# will spin for the full timeout on completed runs.
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":250,"status":"completed","conclusion":null,"workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/250"}]'
    ;;
  run:view)
    echo '{"databaseId":250,"status":"completed","conclusion":null,"workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/250","jobs":[]}'
    ;;
esac
EOF

run_test "pass" "0" "completed (null conclusion) → status: pass, exit 0"

# ---------------------------------------------------------------------------
# Test: cancelled → fail (with reason: cancelled)
# Issue #87: cancelled/skipped runs must NOT be reported as pass — the ship
# and session/end skills gate on `status: pass` and would otherwise advance
# onto an aborted CI run.
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":300,"status":"completed","conclusion":"cancelled","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/300"}]'
    ;;
  run:view)
    echo '{"databaseId":300,"status":"completed","conclusion":"cancelled","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/300","jobs":[]}'
    ;;
esac
EOF

run_test "fail" "0" "cancelled → status: fail, exit 0"

# Verify the cancelled run also emits `reason: cancelled`
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_reason=$(echo "$output" | grep '^reason:' | sed 's/^reason: *//')
if [[ "$got_reason" == "cancelled" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "cancelled → reason: cancelled"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "cancelled → reason: cancelled" "$got_reason"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: no-workflow — no runs found
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[]'
    ;;
  run:view)
    echo '{}'
    ;;
esac
EOF

run_test "no-workflow" "3" "no runs → status: no-workflow, exit 3"

# ---------------------------------------------------------------------------
# Test: timeout — run stays in_progress past deadline
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":500,"status":"in_progress","conclusion":null,"workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/500"}]'
    ;;
  run:view)
    echo '{"databaseId":500,"status":"in_progress","conclusion":null,"workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/500","jobs":[]}'
    ;;
esac
EOF

run_test "timeout" "2" "in_progress past deadline → status: timeout, exit 2"

# ---------------------------------------------------------------------------
# Test: missing --branch → usage error, exit 1
# ---------------------------------------------------------------------------

echo "── run watch: argument validation ──"

exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch 2>/dev/null || exit_code=$?
if [[ "$exit_code" == "1" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "missing --branch → exit 1"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got exit %s)\n" "missing --branch → exit 1" "$exit_code"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: url field present in output
# ---------------------------------------------------------------------------

echo "── run watch: output fields ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":600,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/600"}]'
    ;;
  run:view)
    echo '{"databaseId":600,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/600","jobs":[{"databaseId":1,"name":"build","conclusion":"success","status":"completed","steps":[]}]}'
    ;;
esac
EOF

output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_url=$(echo "$output" | grep '^url:' | sed 's/^url: *//')
if [[ "$got_url" == *"github.com"* ]]; then
  printf "  \033[32m✓\033[0m %s\n" "output includes url field"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "output includes url field" "$got_url"
  ((FAIL++)) || true
fi

got_duration=$(echo "$output" | grep '^duration:' | sed 's/^duration: *//')
if [[ "$got_duration" == *"s" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "output includes duration field"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "output includes duration field" "$got_duration"
  ((FAIL++)) || true
fi

# ===========================================================================
# PR-based path tests (GitHub statusCheckRollup)
# ===========================================================================

echo "── run watch: PR-based CI status ──"

# Helper for PR-path tests — mock returns a PR so the PR path is used
run_pr_test() {
  local expected_status="$1" expected_exit="$2" label="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
    --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || exit_code=$?

  local got_status
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')

  if [[ "$got_status" == "$expected_status" && "$exit_code" == "$expected_exit" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected status=%s exit=%s, got status=%s exit=%s)\n" \
      "$label" "$expected_status" "$expected_exit" "$got_status" "$exit_code"
    ((FAIL++)) || true
  fi
}

# PR path: all checks pass
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    # Check for --json flag to distinguish lookup vs status poll
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":42,"url":"https://github.com/test/repo/pull/42"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/42","statusCheckRollup":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}]}'
    fi
    ;;
esac
EOF

run_pr_test "pass" "0" "PR checks all pass → status: pass, exit 0"

# PR path: a check fails
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":43,"url":"https://github.com/test/repo/pull/43"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/43","statusCheckRollup":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]}'
    fi
    ;;
  run:list)
    echo '[]'
    ;;
esac
EOF

run_pr_test "fail" "0" "PR check failure → status: fail, exit 0"

# Verify failed_jobs contains the failed check name
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_failed=$(echo "$output" | grep '^failed_jobs:' | sed 's/^failed_jobs: *//')
if [[ "$got_failed" == "lint" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "PR check failure → failed_jobs includes 'lint'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "PR check failure → failed_jobs includes 'lint'" "$got_failed"
  ((FAIL++)) || true
fi

# PR path: PR already merged
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":44,"url":"https://github.com/test/repo/pull/44"}'
    else
      echo '{"state":"MERGED","url":"https://github.com/test/repo/pull/44","statusCheckRollup":[]}'
    fi
    ;;
esac
EOF

run_pr_test "pass" "0" "PR merged → status: pass, exit 0"

# PR path: PR closed without merge
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":45,"url":"https://github.com/test/repo/pull/45"}'
    else
      echo '{"state":"CLOSED","url":"https://github.com/test/repo/pull/45","statusCheckRollup":[]}'
    fi
    ;;
esac
EOF

run_pr_test "closed" "0" "PR closed → status: closed, exit 0"

# PR path: checks still pending → timeout
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":46,"url":"https://github.com/test/repo/pull/46"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/46","statusCheckRollup":[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null}]}'
    fi
    ;;
esac
EOF

run_pr_test "timeout" "2" "PR checks pending → status: timeout, exit 2"

# ===========================================================================
# Pre-check tests — verify watch exits immediately for terminal states
# ===========================================================================

echo "── run watch: pre-check (skips initial delay) ──"

# Helper that verifies both status and duration: 0s (proves pre-check fired)
run_precheck_test() {
  local expected_status="$1" expected_exit="$2" label="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  # Use a large initial-delay — if pre-check works, we never sleep it
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
    --branch "test-branch" --initial-delay 30 --timeout 60 --interval 10 2>/dev/null) || exit_code=$?

  local got_status got_duration
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
  got_duration=$(echo "$output" | grep '^duration:' | head -1 | sed 's/^duration: *//')

  if [[ "$got_status" == "$expected_status" && "$exit_code" == "$expected_exit" && "$got_duration" == "0s" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected status=%s exit=%s duration=0s, got status=%s exit=%s duration=%s)\n" \
      "$label" "$expected_status" "$expected_exit" "$got_status" "$exit_code" "$got_duration"
    ((FAIL++)) || true
  fi
}

# Pre-check: PR already merged
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":50,"url":"https://github.com/test/repo/pull/50"}'
    else
      echo '{"state":"MERGED","url":"https://github.com/test/repo/pull/50","statusCheckRollup":[]}'
    fi
    ;;
esac
EOF

run_precheck_test "pass" "0" "PR already merged → instant exit, duration 0s"

# Pre-check: PR already closed
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":51,"url":"https://github.com/test/repo/pull/51"}'
    else
      echo '{"state":"CLOSED","url":"https://github.com/test/repo/pull/51","statusCheckRollup":[]}'
    fi
    ;;
esac
EOF

run_precheck_test "closed" "0" "PR already closed → instant exit, duration 0s"

# Pre-check: CI already passed (PR path)
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":52,"url":"https://github.com/test/repo/pull/52"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/52","statusCheckRollup":[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]}'
    fi
    ;;
esac
EOF

run_precheck_test "pass" "0" "CI already passed (PR) → instant exit, duration 0s"

# Pre-check: CI already failed (PR path)
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":53,"url":"https://github.com/test/repo/pull/53"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/53","statusCheckRollup":[{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]}'
    fi
    ;;
  run:list)
    echo '[]'
    ;;
esac
EOF

run_precheck_test "fail" "0" "CI already failed (PR) → instant exit, duration 0s"

# Pre-check: CI already passed (fallback path, no PR)
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":700,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/700"}]'
    ;;
  run:view)
    echo '{"databaseId":700,"status":"completed","conclusion":"success","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/700","jobs":[]}'
    ;;
esac
EOF

run_precheck_test "pass" "0" "CI already passed (no PR) → instant exit, duration 0s"

# Pre-check: CI already failed (fallback path, no PR)
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[{"databaseId":800,"status":"completed","conclusion":"failure","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/800"}]'
    ;;
  run:view)
    if [[ "${3:-}" == "--log-failed" || "${4:-}" == "--log-failed" ]]; then
      echo "Error in test step"
      exit 0
    fi
    echo '{"databaseId":800,"status":"completed","conclusion":"failure","workflowName":"CI","headBranch":"test-branch","event":"push","createdAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/actions/runs/800","jobs":[{"databaseId":1,"name":"lint","conclusion":"failure","status":"completed","steps":[]}]}'
    ;;
esac
EOF

run_precheck_test "fail" "0" "CI already failed (no PR) → instant exit, duration 0s"

# Pre-check: CI still pending (PR path) → should NOT pre-check exit, should proceed to poll
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    if [[ "$*" == *"number,url"* ]]; then
      echo '{"number":55,"url":"https://github.com/test/repo/pull/55"}'
    else
      echo '{"state":"OPEN","url":"https://github.com/test/repo/pull/55","statusCheckRollup":[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null}]}'
    fi
    ;;
esac
EOF

# This should timeout (not pre-check exit) since CI is still pending
exit_code=0
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 2 --interval 1 2>/dev/null) || exit_code=$?
got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
if [[ "$got_status" == "timeout" && "$exit_code" == "2" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "CI pending → pre-check does not exit, falls through to poll"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected timeout/2, got %s/%s)\n" \
    "CI pending → pre-check does not exit, falls through to poll" "$got_status" "$exit_code"
  ((FAIL++)) || true
fi

# Pre-check: no runs yet (fallback path) → should NOT pre-check exit
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:view)
    exit 1
    ;;
  run:list)
    echo '[]'
    ;;
esac
EOF

exit_code=0
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 2 --interval 1 2>/dev/null) || exit_code=$?
got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
if [[ "$got_status" == "no-workflow" && "$exit_code" == "3" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "no runs yet → pre-check does not exit, falls through to poll"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (expected no-workflow/3, got %s/%s)\n" \
    "no runs yet → pre-check does not exit, falls through to poll" "$got_status" "$exit_code"
  ((FAIL++)) || true
fi

# ===========================================================================
# Gitea path tests (issue #87 — job-level failure aggregation)
#
# These tests swap the git mock to a Gitea remote and add a tea mock so
# detect_platform picks the gitea code path. They cover:
#   - run-level success masking a failed job → status: fail (the #87 repro)
#   - run-level failure → status: fail
#   - cancelled → status: fail with reason: cancelled
#   - log-grep fallback when the jobs API is unavailable
#   - --branch flag is forwarded to `tea actions runs list`
#   - pre-check path (completed run already present) catches a failed job
# ===========================================================================

echo "── run watch: Gitea outcomes ──"

# Switch the git mock to a Gitea-style remote so detect_platform takes the
# gitea branch. Restored at the end of the section.
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://gitea.example.com/owner/repo.git" ;;
  *) PATH=${PATH#"${0%/*}":}; exec git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# tea login list — the wrapper matches a configured login host against the
# remote host to identify the platform. Return a single login matching the
# git mock host.
cat >"$MOCK_DIR/tea" <<'TEA_HEADER'
#!/usr/bin/env bash
# Mock tea — dispatches on subcommand. Per-test bodies appended below.
TEA_HEADER

write_mock_tea() {
  cat >"$MOCK_DIR/tea" <<'TEA_HEADER'
#!/usr/bin/env bash
# Mock tea — dispatches on subcommand.
case "$1 $2 $3" in
  "login list "*)
    echo '[{"name":"example","url":"https://gitea.example.com","user":"owner"}]'
    exit 0
    ;;
esac
TEA_HEADER
  cat >>"$MOCK_DIR/tea"
  chmod +x "$MOCK_DIR/tea"
}

# Run a watch invocation against the gitea mocks. Mirrors run_test but
# leaves the gh mock alone (it is unused on the gitea path; the wrapper
# does not invoke gh when PLATFORM == "gitea").
gitea_run_test() {
  local expected_status="$1" expected_exit="$2" label="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
    --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || exit_code=$?

  local got_status
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')

  if [[ "$got_status" == "$expected_status" && "$exit_code" == "$expected_exit" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected status=%s exit=%s, got status=%s exit=%s)\n" \
      "$label" "$expected_status" "$expected_exit" "$got_status" "$exit_code"
    ((FAIL++)) || true
  fi
}

# ---------------------------------------------------------------------------
# Mock dispatch shape
#
# After the #103 fix, `git-cli run list` on Gitea calls
# `tea api repos/{owner}/{repo}/actions/runs?limit=N[&status=...]`
# instead of `tea actions runs list`. The mock dispatches:
#   - tea api repos/.../actions/runs?<query>          → workflow_runs list
#   - tea api repos/.../actions/runs/<id>/jobs         → per-job statuses
#   - tea actions runs view <id>                       → single run (run show)
#   - tea actions runs logs <id>                       → log text (run logs)
#
# `head_branch` is populated on Gitea runs even when `branch` is "" (the
# #103 bug); the wrapper normalizes `branch` from `head_branch`.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Test: top-level success, all jobs success → status: pass (sanity baseline)
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":900,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha900","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/900"}'
        ;;
      "runs logs") echo "all green" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[{"id":1,"name":"build","status":"completed","conclusion":"success"}],"total_count":1}'
        ;;
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":900,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha900","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/900"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "pass" "0" "[gitea] all jobs success → status: pass"

# ---------------------------------------------------------------------------
# Test: #87 repro — top-level success, one job failure → status: fail
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":879,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha879","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/879"}'
        ;;
      "runs logs") echo "Job 'lint' failed" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[{"id":2,"name":"lint","status":"completed","conclusion":"failure"},{"id":3,"name":"merge","status":"completed","conclusion":"skipped"}],"total_count":2}'
        ;;
      *actions/runs*)
        # Gitea bug: top-level run reads success even though a job failed.
        echo '{"total_count":1,"workflow_runs":[{"id":879,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha879","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/879"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "fail" "0" "[gitea] #87 — run success masks job failure → status: fail"

# Verify the failed_jobs field names the failed job
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_failed=$(echo "$output" | grep '^failed_jobs:' | sed 's/^failed_jobs: *//')
if [[ "$got_failed" == "lint" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] #87 — failed_jobs includes 'lint'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "[gitea] #87 — failed_jobs includes 'lint'" "$got_failed"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: top-level failure → status: fail
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":880,"status":"completed","conclusion":"failure","name":"ci.yml","head_branch":"test-branch","head_sha":"sha880","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":20,"url":"https://gitea.example.com/owner/repo/actions/runs/880"}'
        ;;
      "runs logs") echo "Job 'build' failed" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[{"id":4,"name":"build","status":"completed","conclusion":"failure"}],"total_count":1}'
        ;;
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":880,"status":"completed","conclusion":"failure","name":"ci.yml","head_branch":"test-branch","head_sha":"sha880","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":20,"url":"https://gitea.example.com/owner/repo/actions/runs/880"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "fail" "0" "[gitea] top-level failure → status: fail"

# ---------------------------------------------------------------------------
# Test: cancelled → status: fail with reason: cancelled
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":881,"status":"cancelled","conclusion":"cancelled","name":"ci.yml","head_branch":"test-branch","head_sha":"sha881","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":5,"url":"https://gitea.example.com/owner/repo/actions/runs/881"}'
        ;;
      "runs logs") echo "" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[],"total_count":0}'
        ;;
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":881,"status":"cancelled","conclusion":"cancelled","name":"ci.yml","head_branch":"test-branch","head_sha":"sha881","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":5,"url":"https://gitea.example.com/owner/repo/actions/runs/881"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "fail" "0" "[gitea] cancelled run → status: fail"

output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_reason=$(echo "$output" | grep '^reason:' | sed 's/^reason: *//')
if [[ "$got_reason" == "cancelled" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] cancelled → reason: cancelled"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "[gitea] cancelled → reason: cancelled" "$got_reason"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: jobs API unavailable, log-grep fallback finds "Job 'lint' failed"
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":882,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha882","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/882"}'
        ;;
      "runs logs")
        # Older Gitea: jobs API absent; the log dump is the only signal.
        printf "step output...\nJob 'lint' failed\nmore output\n"
        ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        # Older Gitea: endpoint not implemented — return non-zero/empty.
        exit 1
        ;;
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":882,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha882","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/882"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "fail" "0" "[gitea] log-grep fallback → status: fail"

output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 0 --timeout 3 --interval 1 2>/dev/null) || true
got_failed=$(echo "$output" | grep '^failed_jobs:' | sed 's/^failed_jobs: *//')
if [[ "$got_failed" == "lint" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] log-grep fallback → failed_jobs includes 'lint'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "[gitea] log-grep fallback → failed_jobs includes 'lint'" "$got_failed"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test (#103): pull_request run with empty branch + populated head_branch
# correlates to --branch and run watch reports success. Repro: the run lists
# `branch: ""` (Gitea omits branch on pull_request events) but `head_branch`
# carries the actual branch name.
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":920,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha920","event":"pull_request","run_started_at":"2024-01-01T00:00:00Z","duration":41,"url":"https://gitea.example.com/owner/repo/actions/runs/920"}'
        ;;
      "runs logs") echo "" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[{"id":11,"name":"build","status":"completed","conclusion":"success"}],"total_count":1}'
        ;;
      *actions/runs*)
        # Repro of #103: branch is "" (Gitea sets it empty for pull_request
        # events), but head_branch is populated.
        echo '{"total_count":1,"workflow_runs":[{"id":920,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha920","branch":"","event":"pull_request","run_started_at":"2024-01-01T00:00:00Z","duration":41,"url":"https://gitea.example.com/owner/repo/actions/runs/920"}]}'
        ;;
    esac
    ;;
esac
EOF

gitea_run_test "pass" "0" "[gitea] #103 — pull_request run correlates via head_branch → status: pass"

# ---------------------------------------------------------------------------
# Test (#103): run list --branch X filters client-side by head_branch.
# Mock returns two runs: one matching, one not. Expect exactly one element
# with branch=test-branch in the output.
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  api)
    case "$2" in
      *actions/runs*)
        echo '{"total_count":2,"workflow_runs":[
          {"id":1001,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha1001","branch":"","event":"pull_request","run_started_at":"2024-01-01T00:00:00Z","duration":10,"url":"u1"},
          {"id":1002,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"other","head_sha":"sha1002","branch":"","event":"pull_request","run_started_at":"2024-01-01T00:00:00Z","duration":11,"url":"u2"}
        ]}'
        ;;
    esac
    ;;
esac
EOF

list_json=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run list --branch test-branch --limit 5 2>/dev/null) || true
list_count=$(echo "$list_json" | jq 'length')
list_branch=$(echo "$list_json" | jq -r '.[0].branch // empty')
list_sha=$(echo "$list_json" | jq -r '.[0].head_sha // empty')
if [[ "$list_count" == "1" && "$list_branch" == "test-branch" && "$list_sha" == "sha1001" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] #103 — run list --branch filters client-side, head_sha populated"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (count=%s branch=%s sha=%s)\n" \
    "[gitea] #103 — run list --branch filters client-side, head_sha populated" "$list_count" "$list_branch" "$list_sha"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test (#103): no-workflow stderr distinguishes "no runs" from "runs exist
# but none correlate to branch". This is defense in depth — the
# head_branch correlation above should keep this branch from firing in
# normal operation.
# ---------------------------------------------------------------------------

# Case A: no runs at all → stderr says "No CI workflow found".
write_mock_tea <<'EOF'
case "$1" in
  api)
    case "$2" in
      *actions/runs*) echo '{"total_count":0,"workflow_runs":[]}' ;;
    esac
    ;;
esac
EOF

exit_code=0
stderr_out=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch test-branch --initial-delay 0 --timeout 1 --interval 1 2>&1 >/dev/null) || exit_code=$?
if [[ "$exit_code" == "3" ]] && echo "$stderr_out" | grep -q "No CI workflow found"; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] #103 — no runs → stderr says 'No CI workflow found'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (exit=%s stderr=%s)\n" \
    "[gitea] #103 — no runs → stderr says 'No CI workflow found'" "$exit_code" "$stderr_out"
  ((FAIL++)) || true
fi

# Case B: runs exist but none match branch → stderr says "none correlate".
write_mock_tea <<'EOF'
case "$1" in
  api)
    case "$2" in
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":2001,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"unrelated","head_sha":"sha2001","branch":"","event":"pull_request","run_started_at":"2024-01-01T00:00:00Z","duration":10,"url":"u"}]}'
        ;;
    esac
    ;;
esac
EOF

exit_code=0
stderr_out=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch test-branch --initial-delay 0 --timeout 1 --interval 1 2>&1 >/dev/null) || exit_code=$?
if [[ "$exit_code" == "3" ]] && echo "$stderr_out" | grep -q "none correlate to branch"; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] #103 — runs exist but none match → stderr says 'none correlate'"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (exit=%s stderr=%s)\n" \
    "[gitea] #103 — runs exist but none match → stderr says 'none correlate'" "$exit_code" "$stderr_out"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: pre-check path — completed run with failed job present before loop
# ---------------------------------------------------------------------------

write_mock_tea <<'EOF'
case "$1" in
  actions)
    case "$2 $3" in
      "runs view")
        echo '{"id":884,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha884","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/884"}'
        ;;
      "runs logs") echo "Job 'lint' failed" ;;
    esac
    ;;
  api)
    case "$2" in
      *actions/runs/*/jobs)
        echo '{"jobs":[{"id":8,"name":"lint","status":"completed","conclusion":"failure"}],"total_count":1}'
        ;;
      *actions/runs*)
        echo '{"total_count":1,"workflow_runs":[{"id":884,"status":"completed","conclusion":"success","name":"ci.yml","head_branch":"test-branch","head_sha":"sha884","branch":"","event":"push","run_started_at":"2024-01-01T00:00:00Z","duration":15,"url":"https://gitea.example.com/owner/repo/actions/runs/884"}]}'
        ;;
    esac
    ;;
esac
EOF

# initial-delay 60 forces use of the pre-check path: if it doesn't catch the
# failed job, the test would hang on the initial sleep.
exit_code=0
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch \
  --branch "test-branch" --initial-delay 60 --timeout 3 --interval 1 2>/dev/null) || exit_code=$?
got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
got_duration=$(echo "$output" | grep '^duration:' | sed 's/^duration: *//')
if [[ "$got_status" == "fail" && "$exit_code" == "0" && "$got_duration" == "0s" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "[gitea] pre-check catches failed job → instant exit"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (status=%s exit=%s duration=%s)\n" \
    "[gitea] pre-check catches failed job → instant exit" "$got_status" "$exit_code" "$got_duration"
  ((FAIL++)) || true
fi

# Restore the GitHub git mock so any future tests added below still see github.
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/test/repo.git" ;;
  *) PATH=${PATH#"${0%/*}":}; exec git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"
rm -f "$MOCK_DIR/tea"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
