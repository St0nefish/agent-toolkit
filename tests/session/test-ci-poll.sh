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
  *) command git "$@" ;;
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
# Test: cancelled → treated as pass
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

run_test "pass" "0" "cancelled → status: pass, exit 0"

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

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
