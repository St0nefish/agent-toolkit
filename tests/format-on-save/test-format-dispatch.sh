#!/usr/bin/env bash
# test-format-dispatch.sh — Verify format-on-save dispatches to the correct
# formatter for .rs and .toml files, including cargo fmt Cargo.toml lookup,
# rustfmt fallback, and missing-tool warnings.
#
# Uses mock binaries via PATH manipulation and tests both Claude Code and
# Copilot CLI payload formats.
#
# Usage: bash tests/format-on-save/test-format-dispatch.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../plugins-claude/format-on-save/scripts/format-on-save.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

MOCK_DIR=""
WORK_DIR=""
cleanup() {
  [[ -n "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"
  [[ -n "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT
MOCK_DIR=$(mktemp -d)
WORK_DIR=$(mktemp -d)

LOG="$MOCK_DIR/calls.log"
STDERR_LOG="$MOCK_DIR/stderr.log"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

claude_payload() {
  jq -n --arg fp "$1" '{tool_name:"Write",tool_input:{file_path:$fp}}'
}

copilot_payload() {
  jq -n --arg fp "$1" '{toolName:"write",toolArgs:({file_path:$fp}|tojson)}'
}

# Create a helper directory with symlinks to essential tools only.
# This guarantees cargo/rustfmt/taplo are NOT found unless explicitly mocked.
HELPER_BIN=$(mktemp -d)
for tool in bash env jq cat dirname grep sed awk printf echo test tr head tail \
  sort uniq wc cut mktemp rm mkdir touch chmod cp mv tee; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$src" "$HELPER_BIN/$tool"
done
# Also need [ (test bracket)
[[ -f /bin/[ ]] && ln -sf /bin/[ "$HELPER_BIN/["

make_path() {
  local mock="$1"
  echo "${mock}:${HELPER_BIN}"
}

assert_called() {
  local label="$1" log_file="$2" expected="$3"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  if grep -qF "$expected" "$log_file" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected '%s' in log)\n" "$label" "$expected"
    ((FAIL++)) || true
  fi
}

assert_not_called() {
  local label="$1" log_file="$2" unexpected="$3"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  if ! grep -qF "$unexpected" "$log_file" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (unexpected '%s' found in log)\n" "$label" "$unexpected"
    ((FAIL++)) || true
  fi
}

assert_warns() {
  local label="$1" stderr_file="$2" expected="$3"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  if grep -qF "$expected" "$stderr_file" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected '%s' in stderr)\n" "$label" "$expected"
    ((FAIL++)) || true
  fi
}

assert_exit_zero() {
  local label="$1" exit_code="$2"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  if [[ "$exit_code" -eq 0 ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (exit %s, expected 0)\n" "$label" "$exit_code"
    ((FAIL++)) || true
  fi
}

# Run hook and capture exit code + stderr; log file is written by mocks
run_hook() {
  local format="$1" file_path="$2" test_path="$3"
  local ec=0
  if [[ "$format" == "claude" ]]; then
    claude_payload "$file_path" | PATH="$test_path" bash "$HOOK_SCRIPT" \
      >/dev/null 2>"$STDERR_LOG" || ec=$?
  else
    copilot_payload "$file_path" | PATH="$test_path" bash "$HOOK_SCRIPT" \
      >/dev/null 2>"$STDERR_LOG" || ec=$?
  fi
  echo "$ec"
}

# ---------------------------------------------------------------------------
# Mock setup
# ---------------------------------------------------------------------------

# Create mock dir with all three tools (cargo, rustfmt, taplo)
FULL_MOCK=$(mktemp -d)
cat >"$FULL_MOCK/cargo" <<MOCK
#!/usr/bin/env bash
echo "cargo \$*" >>"$LOG"
MOCK
cat >"$FULL_MOCK/rustfmt" <<MOCK
#!/usr/bin/env bash
echo "rustfmt \$*" >>"$LOG"
MOCK
cat >"$FULL_MOCK/taplo" <<MOCK
#!/usr/bin/env bash
echo "taplo \$*" >>"$LOG"
MOCK
chmod +x "$FULL_MOCK/cargo" "$FULL_MOCK/rustfmt" "$FULL_MOCK/taplo"

# Mock dir with only rustfmt (no cargo)
RUSTFMT_ONLY=$(mktemp -d)
cat >"$RUSTFMT_ONLY/rustfmt" <<MOCK
#!/usr/bin/env bash
echo "rustfmt \$*" >>"$LOG"
MOCK
chmod +x "$RUSTFMT_ONLY/rustfmt"

# Empty mock dir (no rust/toml tools at all)
EMPTY_MOCK=$(mktemp -d)

# Build isolated PATHs
PATH_ALL=$(make_path "$FULL_MOCK")
PATH_RUSTFMT_ONLY=$(make_path "$RUSTFMT_ONLY")
PATH_NONE=$(make_path "$EMPTY_MOCK")

# Create fixture files
mkdir -p "$WORK_DIR/with-cargo/src"
touch "$WORK_DIR/with-cargo/Cargo.toml"
touch "$WORK_DIR/with-cargo/src/main.rs"
mkdir -p "$WORK_DIR/plain-rs"
touch "$WORK_DIR/plain-rs/standalone.rs"
touch "$WORK_DIR/config.toml"

# ---------------------------------------------------------------------------
# Tests: .rs with Cargo.toml in parent
# ---------------------------------------------------------------------------

echo "── .rs file with Cargo.toml ──"

for fmt in claude copilot; do
  : >"$LOG"
  ec=$(run_hook "$fmt" "$WORK_DIR/with-cargo/src/main.rs" "$PATH_ALL")
  assert_called "[$fmt] cargo fmt invoked with --manifest-path" "$LOG" "cargo fmt --manifest-path"
  assert_not_called "[$fmt] rustfmt not invoked" "$LOG" "rustfmt"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Tests: .rs without Cargo.toml → rustfmt fallback
# ---------------------------------------------------------------------------

echo "── .rs file without Cargo.toml ──"

for fmt in claude copilot; do
  : >"$LOG"
  ec=$(run_hook "$fmt" "$WORK_DIR/plain-rs/standalone.rs" "$PATH_ALL")
  assert_called "[$fmt] rustfmt invoked for standalone .rs" "$LOG" "rustfmt"
  assert_not_called "[$fmt] cargo not invoked" "$LOG" "cargo"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Tests: .toml → taplo
# ---------------------------------------------------------------------------

echo "── .toml file ──"

for fmt in claude copilot; do
  : >"$LOG"
  ec=$(run_hook "$fmt" "$WORK_DIR/config.toml" "$PATH_ALL")
  assert_called "[$fmt] taplo invoked for .toml" "$LOG" "taplo format"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Tests: .rs with cargo missing → rustfmt fallback
# ---------------------------------------------------------------------------

echo "── .rs file, cargo missing ──"

for fmt in claude copilot; do
  : >"$LOG"
  ec=$(run_hook "$fmt" "$WORK_DIR/with-cargo/src/main.rs" "$PATH_RUSTFMT_ONLY")
  assert_called "[$fmt] rustfmt fallback when cargo missing" "$LOG" "rustfmt"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Tests: .rs with both cargo and rustfmt missing → warn and skip
# ---------------------------------------------------------------------------

echo "── .rs file, cargo + rustfmt missing ──"

for fmt in claude copilot; do
  : >"$LOG"
  ec=$(run_hook "$fmt" "$WORK_DIR/with-cargo/src/main.rs" "$PATH_NONE")
  assert_warns "[$fmt] warns about missing tools" "$STDERR_LOG" "not found"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Tests: .toml with taplo missing → warn and skip
# ---------------------------------------------------------------------------

echo "── .toml file, taplo missing ──"

for fmt in claude copilot; do
  ec=$(run_hook "$fmt" "$WORK_DIR/config.toml" "$PATH_NONE")
  assert_warns "[$fmt] warns about missing taplo" "$STDERR_LOG" "taplo not found"
  assert_exit_zero "[$fmt] exits 0" "$ec"
done

# ---------------------------------------------------------------------------
# Cleanup extra temp dirs
# ---------------------------------------------------------------------------

rm -rf "$FULL_MOCK" "$RUSTFMT_ONLY" "$EMPTY_MOCK" "$HELPER_BIN"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
