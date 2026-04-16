#!/usr/bin/env bash
# test-pr-create.sh — Test harness for git-cli pr create --base default detection.
# Uses mock gh/git scripts via PATH injection.
#
# Usage: bash tests/git-cli/test-pr-create.sh [filter]

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
  local expected_exit="$1" label="$2"
  shift 2
  local extra_args=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output exit_code
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
    "${extra_args[@]}" 2>"$MOCK_DIR/stderr") || exit_code=$?

  # Return output and exit code via globals for caller assertions
  TEST_OUTPUT="$output"
  TEST_STDERR=$(cat "$MOCK_DIR/stderr")
  TEST_EXIT="$exit_code"

  if [[ "$exit_code" == "$expected_exit" ]]; then
    return 0
  else
    return 1
  fi
}

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}

write_mock_gh() {
  cat >"$MOCK_DIR/gh" <<'MOCK_HEADER'
#!/usr/bin/env bash
# Mock gh script for pr create tests
MOCK_HEADER
  cat >>"$MOCK_DIR/gh"
  chmod +x "$MOCK_DIR/gh"
}

# Mock git so platform detection works (returns github.com remote)
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/owner/repo.git" ;;
  "config user.name") echo "testuser" ;;
  *) command git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# ---------------------------------------------------------------------------
# Test: --base omitted → auto-detects default branch
# ---------------------------------------------------------------------------

echo "── pr create: --base default detection ──"

# Capture args passed to gh pr create via a file
ARGS_FILE="$MOCK_DIR/.gh_args"

cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
case "\$1:\$2" in
  repo:view)
    # repo default-branch detection
    echo "main"
    ;;
  pr:create)
    # Capture all args for assertion
    echo "\$@" > "$ARGS_FILE"
    echo "https://github.com/owner/repo/pull/1"
    ;;
  api:user)
    echo '{"login":"testuser"}'
    ;;
  api:*)
    echo '{"login":"testuser"}'
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

if run_test "0" "base omitted → auto-detects default branch" \
  --title "Test PR" --head "feature-branch"; then
  # Verify --base main was passed to gh pr create
  gh_args=$(cat "$ARGS_FILE" 2>/dev/null || echo "")
  if echo "$gh_args" | grep -q -- "--base main"; then
    pass "base omitted → auto-detects default branch, passes --base main"
  else
    fail "base omitted → auto-detects default branch" "gh args: $gh_args"
  fi
else
  fail "base omitted → auto-detects default branch" "exit=$TEST_EXIT, stderr=$TEST_STDERR"
fi

# ---------------------------------------------------------------------------
# Test: --base explicitly provided → uses it directly
# ---------------------------------------------------------------------------

cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
case "\$1:\$2" in
  repo:view)
    # Should NOT be called when --base is provided
    echo "UNEXPECTED_CALL" > "$ARGS_FILE.default_branch_called"
    echo "main"
    ;;
  pr:create)
    echo "\$@" > "$ARGS_FILE"
    echo "https://github.com/owner/repo/pull/2"
    ;;
  api:user)
    echo '{"login":"testuser"}'
    ;;
  api:*)
    echo '{"login":"testuser"}'
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"
rm -f "$ARGS_FILE.default_branch_called"

if run_test "0" "base provided → uses it directly" \
  --title "Test PR" --head "feature-branch" --base "develop"; then
  gh_args=$(cat "$ARGS_FILE" 2>/dev/null || echo "")
  if echo "$gh_args" | grep -q -- "--base develop"; then
    pass "base provided → uses --base develop"
  else
    fail "base provided → uses --base develop" "gh args: $gh_args"
  fi
else
  fail "base provided → uses it directly" "exit=$TEST_EXIT, stderr=$TEST_STDERR"
fi

# ---------------------------------------------------------------------------
# Test: --base omitted + default-branch detection fails → error
# ---------------------------------------------------------------------------

cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
case "\$1:\$2" in
  repo:view)
    echo "error: not authenticated" >&2
    exit 1
    ;;
  api:user)
    echo '{"login":"testuser"}'
    ;;
  api:*)
    echo '{"login":"testuser"}'
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

if run_test "1" "base omitted + detection fails → error" \
  --title "Test PR" --head "feature-branch"; then
  if echo "$TEST_STDERR" | grep -q "could not detect default branch"; then
    pass "base omitted + detection fails → helpful error message"
  else
    fail "base omitted + detection fails → error" "stderr: $TEST_STDERR"
  fi
else
  # Exit code 1 is also acceptable (die_usage exits 1, die exits 1)
  if [[ "$TEST_EXIT" -eq 1 ]]; then
    if echo "$TEST_STDERR" | grep -q "could not detect default branch"; then
      pass "base omitted + detection fails → helpful error message"
    else
      fail "base omitted + detection fails → error" "exit=$TEST_EXIT, stderr=$TEST_STDERR"
    fi
  else
    fail "base omitted + detection fails → error" "exit=$TEST_EXIT, stderr=$TEST_STDERR"
  fi
fi

# ---------------------------------------------------------------------------
# Test: missing --title → usage error
# ---------------------------------------------------------------------------

echo "── pr create: argument validation ──"

# Restore a working mock for validation tests
cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
case "\$1:\$2" in
  repo:view) echo "main" ;;
  api:*) echo '{"login":"testuser"}' ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create --head "branch" 2>/dev/null || exit_code=$?
if [[ "$exit_code" == "1" ]]; then
  pass "missing --title → exit 1"
else
  fail "missing --title → exit 1" "got exit $exit_code"
fi

# Test: missing --head → usage error
exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create --title "Test" 2>/dev/null || exit_code=$?
if [[ "$exit_code" == "1" ]]; then
  pass "missing --head → exit 1"
else
  fail "missing --head → exit 1" "got exit $exit_code"
fi

# ---------------------------------------------------------------------------
# Test: --body reads from stdin (heredoc)
# ---------------------------------------------------------------------------

echo "── pr create: --body stdin ──"

BODY_FILE="$MOCK_DIR/.gh_body"

cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
# Capture the value passed to --body into BODY_FILE
args=("\$@")
case "\$1:\$2" in
  repo:view) echo "main" ;;
  pr:create)
    for ((i=0; i<\${#args[@]}; i++)); do
      if [[ "\${args[\$i]}" == "--body" ]]; then
        printf '%s' "\${args[\$((i+1))]}" > "$BODY_FILE"
      fi
    done
    echo "https://github.com/owner/repo/pull/3"
    ;;
  api:*) echo '{"login":"testuser"}' ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

exit_code=0
output=$(
  PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
    --title "Stdin PR" --head "feature" --body <<'BODY_EOF' 2>"$MOCK_DIR/stderr"
## Summary
multi-line body from stdin

- bullet one
- bullet two
BODY_EOF
) || exit_code=$?

if [[ "$exit_code" == "0" ]] && [[ -f "$BODY_FILE" ]] &&
  grep -q "multi-line body from stdin" "$BODY_FILE" &&
  grep -q "bullet one" "$BODY_FILE"; then
  pass "--body reads heredoc from stdin and passes to gh"
else
  fail "--body reads heredoc from stdin" \
    "exit=$exit_code body=$(cat "$BODY_FILE" 2>/dev/null) stderr=$(cat "$MOCK_DIR/stderr")"
fi

# --body with no stdin (terminal) should error
exit_code=0
PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
  --title "No stdin" --head "feature" --body </dev/null 2>"$MOCK_DIR/stderr" >/dev/null || exit_code=$?
# /dev/null satisfies the `-t 0` check (not a terminal), so gh will be called with empty body.
# The real "terminal" path can't be exercised non-interactively, so we skip that assertion.
if [[ "$exit_code" == "0" ]]; then
  pass "--body with empty stdin (pipe from /dev/null) succeeds with empty body"
else
  fail "--body with empty stdin" "exit=$exit_code stderr=$(cat "$MOCK_DIR/stderr")"
fi

# --body-file - is an alias for stdin
cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
args=("\$@")
case "\$1:\$2" in
  repo:view) echo "main" ;;
  pr:create)
    for ((i=0; i<\${#args[@]}; i++)); do
      if [[ "\${args[\$i]}" == "--body" ]]; then
        printf '%s' "\${args[\$((i+1))]}" > "$BODY_FILE"
      fi
    done
    echo "https://github.com/owner/repo/pull/4"
    ;;
  api:*) echo '{"login":"testuser"}' ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

exit_code=0
echo "body via body-file dash" | PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
  --title "Dash PR" --head "feature" --body-file - 2>"$MOCK_DIR/stderr" >/dev/null || exit_code=$?

if [[ "$exit_code" == "0" ]] && grep -q "body via body-file dash" "$BODY_FILE"; then
  pass "--body-file - reads stdin"
else
  fail "--body-file - reads stdin" \
    "exit=$exit_code body=$(cat "$BODY_FILE" 2>/dev/null) stderr=$(cat "$MOCK_DIR/stderr")"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
