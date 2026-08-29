#!/usr/bin/env bash
# test-body-args.sh — Test harness for git-cli parse_body_args().
# Covers --body TEXT (inline), --body-file - (stdin via pipe/heredoc), the
# no-value error, and the no-hang guard on an open/silent stdin pipe (#114).
# Uses mock gh/git scripts via PATH injection.
#
# Usage: bash tests/git-cli/test-body-args.sh [filter]

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

BODY_FILE="$MOCK_DIR/.captured_body"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}

skip_filtered() {
  # Returns 0 (skip) when a filter is set and does not match the label.
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

# Mock git so platform detection resolves to github.
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/owner/repo.git" ;;
  "config user.name") echo "testuser" ;;
  *) PATH=${PATH#"${0%/*}":}; exec git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# Mock gh: capture the inline body into BODY_FILE. issue/pr create still pass it
# via --body; issue/pr comment now post via `gh api ... -f body=VALUE`, so capture
# both forms. `gh api user` (detect_current_user) returns a login.
cat >"$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
args=("\$@")
case "\$1:\$2" in
  repo:view) echo "main" ;;
  api:user)  echo "testuser" ;;
  api:*)
    # Raw api passthrough (comment add/edit): capture -f body=VALUE.
    for ((i=0; i<\${#args[@]}; i++)); do
      if [[ "\${args[\$i]}" == "-f" && "\${args[\$((i+1))]}" == body=* ]]; then
        printf '%s' "\${args[\$((i+1))]#body=}" > "$BODY_FILE"
      fi
    done
    echo '{"id":1,"body":"x","html_url":"https://github.com/owner/repo/issues/42#issuecomment-1","user":{"login":"testuser"},"created_at":"t"}'
    ;;
  *)
    for ((i=0; i<\${#args[@]}; i++)); do
      if [[ "\${args[\$i]}" == "--body" ]]; then
        printf '%s' "\${args[\$((i+1))]}" > "$BODY_FILE"
      fi
    done
    echo "https://github.com/owner/repo/pull/1"
    ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/gh"

run_gh() {
  # run_gh <stdin-source> -- <git-cli args...>; sets EXIT, captures stderr.
  rm -f "$BODY_FILE"
  local stdin_src="$1"
  shift
  [[ "$1" == "--" ]] && shift
  EXIT=0
  if [[ "$stdin_src" == "none" ]]; then
    PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" "$@" </dev/null >/dev/null 2>"$MOCK_DIR/stderr" || EXIT=$?
  else
    printf '%s' "$stdin_src" | PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" "$@" >/dev/null 2>"$MOCK_DIR/stderr" || EXIT=$?
  fi
  STDERR=$(cat "$MOCK_DIR/stderr")
}

# ---------------------------------------------------------------------------
# Test: --body TEXT is inline and never reads stdin
# ---------------------------------------------------------------------------

echo "── parse_body_args: --body TEXT inline ──"

label="--body TEXT → inline value reaches gh (pr create)"
if ! skip_filtered "$label"; then
  run_gh none -- pr create --title "T" --head "feature" --body "inline body text"
  if [[ "$EXIT" == "0" ]] && [[ -f "$BODY_FILE" ]] && grep -qx "inline body text" "$BODY_FILE"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$STDERR"
  fi
else ((SKIP++)) || true; fi

label="--body TEXT → inline value reaches gh (issue create, shared parse_body_args)"
if ! skip_filtered "$label"; then
  run_gh none -- issue create --title "T" --body "issue inline"
  if [[ "$EXIT" == "0" ]] && [[ -f "$BODY_FILE" ]] && grep -qx "issue inline" "$BODY_FILE"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$STDERR"
  fi
else ((SKIP++)) || true; fi

label="--body TEXT → inline value reaches gh api (pr comment)"
if ! skip_filtered "$label"; then
  run_gh none -- pr comment 42 --body "looks good"
  if [[ "$EXIT" == "0" ]] && [[ -f "$BODY_FILE" ]] && grep -qx "looks good" "$BODY_FILE"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$STDERR"
  fi
else ((SKIP++)) || true; fi

label="--body with no inline value → exit 1 (requires a value)"
if ! skip_filtered "$label"; then
  run_gh none -- pr create --title "T" --head "feature" --body
  if [[ "$EXIT" == "1" ]] && echo "$STDERR" | grep -q "requires a value"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT stderr=$STDERR"
  fi
else ((SKIP++)) || true; fi

# ---------------------------------------------------------------------------
# Test: --body-file - reads stdin
# ---------------------------------------------------------------------------

echo "── parse_body_args: --body-file - stdin ──"

label="--body-file - reads piped stdin"
if ! skip_filtered "$label"; then
  run_gh "piped via stdin" -- pr create --title "T" --head "feature" --body-file -
  if [[ "$EXIT" == "0" ]] && [[ -f "$BODY_FILE" ]] && grep -q "piped via stdin" "$BODY_FILE"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$STDERR"
  fi
else ((SKIP++)) || true; fi

label="--body-file - reads multi-line heredoc from stdin"
if ! skip_filtered "$label"; then
  rm -f "$BODY_FILE"
  EXIT=0
  PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
    --title "T" --head "feature" --body-file - >/dev/null 2>"$MOCK_DIR/stderr" <<'BODY_EOF' || EXIT=$?
## Summary
line one
line two
BODY_EOF
  if [[ "$EXIT" == "0" ]] && [[ -f "$BODY_FILE" ]] &&
    grep -q "line one" "$BODY_FILE" && grep -q "line two" "$BODY_FILE"; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$(cat "$MOCK_DIR/stderr")"
  fi
else ((SKIP++)) || true; fi

label="--body-file - with EOF stdin (/dev/null) → empty body, succeeds (pr create)"
if ! skip_filtered "$label"; then
  rm -f "$BODY_FILE"
  EXIT=0
  PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
    --title "T" --head "feature" --body-file - </dev/null >/dev/null 2>"$MOCK_DIR/stderr" || EXIT=$?
  # Empty BODY means git-cli passes no --body to gh, so BODY_FILE is never written.
  if [[ "$EXIT" == "0" ]] && [[ ! -f "$BODY_FILE" ]]; then
    pass "$label"
  else
    fail "$label" "exit=$EXIT body='$(cat "$BODY_FILE" 2>/dev/null)' stderr=$(cat "$MOCK_DIR/stderr")"
  fi
else ((SKIP++)) || true; fi

# ---------------------------------------------------------------------------
# Test: no-hang guard — open/silent stdin pipe errors fast instead of blocking
# ---------------------------------------------------------------------------

echo "── parse_body_args: no-hang guard (#114) ──"

label="--body-file - with open silent pipe → errors within timeout, does not hang"
if ! skip_filtered "$label"; then
  EXIT=0
  start=$(date +%s)
  # < <(sleep 8) gives a non-TTY pipe with no data and no EOF for 8s. With a 1s
  # timeout the read must error (~1s); the old cat-based code would block ~8s.
  GIT_CLI_STDIN_TIMEOUT=1 PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr create \
    --title "T" --head "feature" --body-file - >/dev/null 2>"$MOCK_DIR/stderr" < <(sleep 8) || EXIT=$?
  end=$(date +%s)
  elapsed=$((end - start))
  if [[ "$EXIT" == "1" ]] && [[ "$elapsed" -lt 5 ]] && echo "$(cat "$MOCK_DIR/stderr")" | grep -q "timed out"; then
    pass "$label (exited in ${elapsed}s)"
  else
    fail "$label" "exit=$EXIT elapsed=${elapsed}s stderr=$(cat "$MOCK_DIR/stderr")"
  fi
else ((SKIP++)) || true; fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
