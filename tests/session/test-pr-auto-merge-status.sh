#!/usr/bin/env bash
# test-pr-auto-merge-status.sh — Test harness for git-cli pr auto-merge-status.
# Uses mock gh/tea scripts via PATH manipulation to test auto-merge detection.
#
# Usage: bash tests/session/test-pr-auto-merge-status.sh [filter]

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
  local expected_output="$1" expected_exit="$2" label="$3"
  shift 3
  local extra_args=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr auto-merge-status \
    "${extra_args[@]}" 2>/dev/null) || exit_code=$?

  local got_value
  got_value=$(echo "$output" | grep '^auto_merge:' | head -1 | sed 's/^auto_merge: *//')

  if [[ "$got_value" == "$expected_output" && "$exit_code" == "$expected_exit" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected auto_merge=%s exit=%s, got auto_merge=%s exit=%s)\n" \
      "$label" "$expected_output" "$expected_exit" "$got_value" "$exit_code"
    ((FAIL++)) || true
  fi
}

write_mock_gh() {
  cat >"$MOCK_DIR/gh" <<'MOCK_HEADER'
#!/usr/bin/env bash
# Mock gh script for pr auto-merge-status tests
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
# Test: Auto-merge enabled
# ---------------------------------------------------------------------------

echo "── pr auto-merge-status: detection ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":10,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/10"}]'
    ;;
  pr:view)
    echo '{"autoMergeRequest":{"enabledAt":"2024-01-01T00:00:00Z","enabledBy":{"login":"u"},"mergeMethod":"SQUASH"}}'
    ;;
esac
EOF

run_test "true" "0" "auto-merge enabled → auto_merge: true, exit 0" \
  --branch "test-branch"

# ---------------------------------------------------------------------------
# Test: Auto-merge disabled
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":11,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/11"}]'
    ;;
  pr:view)
    echo '{"autoMergeRequest":null}'
    ;;
esac
EOF

run_test "false" "0" "auto-merge disabled → auto_merge: false, exit 0" \
  --branch "test-branch"

# ---------------------------------------------------------------------------
# Test: No PR for branch
# ---------------------------------------------------------------------------

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":99,"title":"Other PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"other-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/99"}]'
    ;;
  pr:view)
    echo '{"autoMergeRequest":null}'
    ;;
esac
EOF

run_test "false" "3" "no PR for branch → auto_merge: false, exit 3" \
  --branch "test-branch"

# ---------------------------------------------------------------------------
# Test: Missing flags → usage error, exit 1
# ---------------------------------------------------------------------------

echo "── pr auto-merge-status: argument validation ──"

exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr auto-merge-status 2>/dev/null || exit_code=$?
if [[ "$exit_code" == "1" ]]; then
  printf "  \033[32m✓\033[0m %s\n" "missing --branch and --number → exit 1"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %s  (got exit %s)\n" "missing --branch and --number → exit 1" "$exit_code"
  ((FAIL++)) || true
fi

# ---------------------------------------------------------------------------
# Test: Direct by number (skips branch resolution)
# ---------------------------------------------------------------------------

echo "── pr auto-merge-status: direct by number ──"

write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[]'
    ;;
  pr:view)
    echo '{"autoMergeRequest":{"enabledAt":"2024-01-01T00:00:00Z"}}'
    ;;
esac
EOF

run_test "true" "0" "--number 10 skips branch resolution → auto_merge: true, exit 0" \
  --number 10

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
