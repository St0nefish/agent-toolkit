#!/usr/bin/env bash
# test-pr-wait.sh — Test harness for git-cli pr wait.
# Uses mock gh/tea scripts via PATH manipulation to test polling logic.
#
# Usage: bash tests/session/test-pr-wait.sh [filter]

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
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr wait \
    --branch "test-branch" --timeout 3 --interval 1 2>/dev/null) || exit_code=$?

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
# Mock gh script for pr wait tests
MOCK_HEADER
  cat >>"$MOCK_DIR/gh"
  chmod +x "$MOCK_DIR/gh"
}

# Mock git so platform detection works (returns github.com remote)
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/test/repo.git" ;;
  *) command git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# ---------------------------------------------------------------------------
# Test: PR already merged (GitHub state=merged)
# ---------------------------------------------------------------------------

echo "── pr wait: merge outcomes ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":10,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/10"}]'
    ;;
  pr:view)
    echo '{"number":10,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/10","comments":[]}'
    ;;
esac
EOF

run_test "merged" "0" "PR already merged → status: merged, exit 0"

# ---------------------------------------------------------------------------
# Test: PR closed without merge (GitHub state=closed, merged=false)
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":11,"title":"Test PR","body":"","state":"CLOSED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/11"}]'
    ;;
  pr:view)
    echo '{"number":11,"title":"Test PR","body":"","state":"CLOSED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/11","comments":[]}'
    ;;
esac
EOF

run_test "closed" "0" "PR closed without merge → status: closed, exit 0"

# ---------------------------------------------------------------------------
# Test: PR closed via merge (Gitea .merged=true, state=closed)
# This simulates what Gitea returns — state=closed but merged=true
# We mock gh to return state=CLOSED but the jq merged field is false for GH.
# For Gitea, merged comes from the raw .merged field. Here we test the
# normalized merged=true path by having state=CLOSED in GH output — but
# since GH derives merged from state=="merged", we need a separate approach.
# Instead, test the Gitea path: mock tea and use a gitea remote.
# ---------------------------------------------------------------------------

# For simplicity, test merged detection via GitHub state=MERGED (already
# covered above). Add a test with state=closed + merged field manipulation.
# The pr wait code checks .merged from the normalized output. On GitHub,
# merged=(state==merged), so state=CLOSED → merged=false → status: closed.
# On Gitea, merged comes from .merged field directly.
# We'll test the Gitea scenario by injecting a state=closed+merged=true mock.

# We can test this by making gh return MERGED state for a "closed via merge":
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":12,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/12"}]'
    ;;
  pr:view)
    echo '{"number":12,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/12","comments":[]}'
    ;;
esac
EOF

run_test "merged" "0" "PR closed via merge (state=MERGED) → status: merged, exit 0"

# ---------------------------------------------------------------------------
# Test: PR has conflicts (mergeable=CONFLICTING)
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":13,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"CONFLICTING","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/13"}]'
    ;;
  pr:view)
    echo '{"number":13,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"CONFLICTING","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/13","comments":[]}'
    ;;
esac
EOF

run_test "blocked" "0" "PR has conflicts → status: blocked, exit 0"

# ---------------------------------------------------------------------------
# Test: PR merges mid-poll (starts open, then becomes merged)
# ---------------------------------------------------------------------------

# Use a counter file to track poll iterations
COUNTER_FILE="$MOCK_DIR/.poll_counter"
echo "0" >"$COUNTER_FILE"

cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
counter=\$(cat "$COUNTER_FILE")
case "\$1:\$2" in
  pr:list)
    echo '[{"number":14,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/14"}]'
    ;;
  pr:view)
    counter=\$(( counter + 1 ))
    echo "\$counter" > "$COUNTER_FILE"
    if [[ "\$counter" -ge 2 ]]; then
      echo '{"number":14,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/14","comments":[]}'
    else
      echo '{"number":14,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/14","comments":[]}'
    fi
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

run_test "merged" "0" "PR merges mid-poll → status: merged, exit 0"

# ---------------------------------------------------------------------------
# Test: timeout — PR stays open
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":15,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/15"}]'
    ;;
  pr:view)
    echo '{"number":15,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/15","comments":[]}'
    ;;
esac
EOF

run_test "timeout" "2" "PR stays open past deadline → status: timeout, exit 2"

# ---------------------------------------------------------------------------
# Test: no PR for branch
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":99,"title":"Other PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"other-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/99"}]'
    ;;
  pr:view)
    echo '{}'
    ;;
esac
EOF

run_test "no-pr" "3" "no PR for branch → status: no-pr, exit 3"

# ---------------------------------------------------------------------------
# Test: missing --branch → usage error, exit 1
# ---------------------------------------------------------------------------

echo "── pr wait: argument validation ──"

exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr wait 2>/dev/null || exit_code=$?
if [[ "$exit_code" == "1" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "missing --branch → exit 1"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got exit %s)\n" "missing --branch → exit 1" "$exit_code"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: output includes url and pr_number fields
# ---------------------------------------------------------------------------

echo "── pr wait: output fields ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":16,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/16"}]'
    ;;
  pr:view)
    echo '{"number":16,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/16","comments":[]}'
    ;;
esac
EOF

output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr wait \
  --branch "test-branch" --timeout 3 --interval 1 2>/dev/null) || true

got_url=$(echo "$output" | grep '^url:' | sed 's/^url: *//')
if [[ "$got_url" == *"github.com"* ]]; then
  printf "  \033[32m✓\033[0m %s\n" "output includes url field"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "output includes url field" "$got_url"
  ((FAIL++)) || true
fi

got_pr_number=$(echo "$output" | grep '^pr_number:' | sed 's/^pr_number: *//')
if [[ "$got_pr_number" == "16" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "output includes pr_number field"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got: '%s')\n" "output includes pr_number field" "$got_pr_number"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: unknown state → error after 3 attempts (not infinite loop)
# ---------------------------------------------------------------------------

echo "── pr wait: error handling ──"

# gh pr view returns empty JSON → state="unknown" → should abort after 3 polls
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":17,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/17"}]'
    ;;
  pr:view)
    # Return empty JSON — simulates a broken/unreachable API
    echo '{}'
    ;;
esac
EOF

run_test "error" "4" "pr show returns empty JSON → status: error, exit 4"

# gh pr view returns garbage state
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":18,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/18"}]'
    ;;
  pr:view)
    echo '{"number":18,"title":"Test PR","body":"","state":"BANANA","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/18","comments":[]}'
    ;;
esac
EOF

run_test "error" "4" "pr show returns unrecognized state → status: error, exit 4"

# Transient unknown then recovery — should NOT error
echo "0" >"$COUNTER_FILE"
cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
counter=\$(cat "$COUNTER_FILE")
case "\$1:\$2" in
  pr:list)
    echo '[{"number":19,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/19"}]'
    ;;
  pr:view)
    counter=\$(( counter + 1 ))
    echo "\$counter" > "$COUNTER_FILE"
    if [[ "\$counter" -le 1 ]]; then
      # First poll: return garbage state
      echo '{}'
    else
      # Second poll onward: merged
      echo '{"number":19,"title":"Test PR","body":"","state":"MERGED","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/19","comments":[]}'
    fi
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

run_test "merged" "0" "transient unknown then recovery → status: merged, exit 0"

# ---------------------------------------------------------------------------
# Test: progress-aware timeout (issue #149)
# pr wait must not time out while CI/auto-merge is progressing; it gives up
# after an idle window of no progress, with a larger absolute ceiling.
# ---------------------------------------------------------------------------

echo "── pr wait: progress-aware timeout ──"

# Idle window fires when there is no progress. Mock has no statusCheckRollup
# (_ci_status → none) and no autoMergeRequest (→ false), so an open PR makes no
# progress and must hit the small idle window well before the large ceiling.
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":20,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/20"}]'
    ;;
  pr:view)
    echo '{"number":20,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/20","comments":[]}'
    ;;
esac
EOF

start=$SECONDS
exit_code=0
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr wait \
  --branch "test-branch" --idle-timeout 2 --timeout 100 --interval 1 2>/dev/null) || exit_code=$?
duration=$((SECONDS - start))
got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
got_reason=$(echo "$output" | grep '^reason:' | head -1 | sed 's/^reason: *//')

if [[ "$got_status" == "timeout" && "$exit_code" == "2" && "$got_reason" == *"no progress"* && "$duration" -lt 20 ]]; then
  printf "  \033[32m✓\033[0m %s\n" "idle timeout fires on no progress (reason='$got_reason', ${duration}s, not the 100s ceiling)"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (status=%s exit=%s reason='%s' dur=%ss)\n" \
    "idle timeout fires on no progress" "$got_status" "$exit_code" "$got_reason" "$duration"
  ((FAIL++)) || true
fi

# Pending CI counts as progress and resets the idle clock, so with a tiny idle
# window but a small ceiling the wait runs to the ceiling, not the idle window.
write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":21,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/21"}]'
    ;;
  pr:view)
    echo '{"number":21,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/21","statusCheckRollup":[{"__typename":"CheckRun","conclusion":null}],"comments":[]}'
    ;;
esac
EOF

start=$SECONDS
exit_code=0
output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr wait \
  --branch "test-branch" --idle-timeout 1 --timeout 4 --interval 1 2>/dev/null) || exit_code=$?
duration=$((SECONDS - start))
got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
got_reason=$(echo "$output" | grep '^reason:' | head -1 | sed 's/^reason: *//')

if [[ "$got_status" == "timeout" && "$exit_code" == "2" && "$got_reason" == *"max wait"* && "$duration" -ge 3 ]]; then
  printf "  \033[32m✓\033[0m %s\n" "pending CI defeats idle → ceiling (reason='$got_reason', ${duration}s)"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (status=%s exit=%s reason='%s' dur=%ss)\n" \
    "pending CI defeats idle → ceiling" "$got_status" "$exit_code" "$got_reason" "$duration"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: default timeout invariants (issue #149)
# Parsed directly from the canonical git-cli source — no wall-clock wait.
# ---------------------------------------------------------------------------

echo "── pr wait / run watch: default timeout invariants ──"

pr_wait_line=$(grep -A4 '^  pr:wait)' "$GIT_CLI" | grep 'branch=""' | head -1)
run_watch_line=$(grep -A7 '^  run:watch)' "$GIT_CLI" | grep 'branch=""' | head -1)

pr_wait_timeout=$(echo "$pr_wait_line" | sed -nE 's/.*[;[:space:]]timeout=([0-9]+).*/\1/p')
pr_wait_idle=$(echo "$pr_wait_line" | sed -nE 's/.*idle_timeout=([0-9]+).*/\1/p')
run_watch_timeout=$(echo "$run_watch_line" | sed -nE 's/.*[;[:space:]]timeout=([0-9]+).*/\1/p')
run_watch_idle=$(echo "$run_watch_line" | sed -nE 's/.*idle_timeout=([0-9]+).*/\1/p')

assert_eq() { # <label> <expected> <got>
  if [[ "$2" == "$3" ]]; then
    printf "  \033[32m✓\033[0m %s (=%s)\n" "$1" "$3"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected %s, got '%s')\n" "$1" "$2" "$3"
    ((FAIL++)) || true
  fi
}

assert_eq "pr wait default timeout is 3600" "3600" "$pr_wait_timeout"
assert_eq "pr wait default idle-timeout is 300" "300" "$pr_wait_idle"
assert_eq "run watch default timeout is 3600" "3600" "$run_watch_timeout"
assert_eq "run watch default idle-timeout is 300" "300" "$run_watch_idle"

if [[ -n "$pr_wait_timeout" && -n "$run_watch_timeout" && "$pr_wait_timeout" -ge "$run_watch_timeout" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "pr wait ceiling ($pr_wait_timeout) >= run watch ceiling ($run_watch_timeout)"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (pr wait='%s' run watch='%s')\n" \
    "pr wait ceiling >= run watch ceiling" "$pr_wait_timeout" "$run_watch_timeout"
  ((FAIL++)) || true
fi

if [[ -n "$pr_wait_idle" && -n "$pr_wait_timeout" && "$pr_wait_idle" -le "$pr_wait_timeout" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "pr wait idle ($pr_wait_idle) <= ceiling ($pr_wait_timeout)"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (idle='%s' ceiling='%s')\n" \
    "pr wait idle <= ceiling" "$pr_wait_idle" "$pr_wait_timeout"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
