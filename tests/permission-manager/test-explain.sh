#!/usr/bin/env bash
# test-explain.sh — Test harness for explain.sh classification trace.
#
# Usage: bash tests/permission-manager/test-explain.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPLAIN_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/explain.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

run_test() {
  local label="$1" command="$2"
  shift 2
  local expected_patterns=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local output
  output=$(bash "$EXPLAIN_SCRIPT" "$command" 2>/dev/null) || true

  local all_matched=true
  local missing=""
  for pattern in "${expected_patterns[@]}"; do
    if ! echo "$output" | grep -qi "$pattern"; then
      all_matched=false
      missing+="  missing: $pattern"$'\n'
    fi
  done

  if [[ "$all_matched" == true ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "%s" "$missing"
    ((FAIL++)) || true
  fi
}

# Check dependencies
if ! command -v shfmt &>/dev/null || ! command -v jq &>/dev/null; then
  echo "SKIP: shfmt and jq are required"
  exit 0
fi

# ===== Single read-only =====
echo "── Basic classification traces ──"
run_test "git status → ALLOW, check_git" \
  "git status" \
  "check_git" "ALLOW" "read-only"

run_test "cargo run → ASK, check_cargo" \
  "cargo run" \
  "check_cargo" "ASK"

# ===== Redirection deny =====
echo "── Redirection traces ──"
run_test "echo foo > output.txt → DENY, redirection" \
  "echo foo > output.txt" \
  "DENY" "redirection"

# ===== Compound command =====
echo "── Compound command traces ──"
run_test "git status && cargo build → Segment 1, Segment 2" \
  "git status && cargo build" \
  "Segment 1" "Segment 2"

# ===== Dangerous find =====
echo "── Dangerous command traces ──"
run_test "find . -delete → DENY, check_find" \
  "find . -delete" \
  "check_find" "DENY"

# ===== Unrecognized command =====
echo "── Unrecognized command traces ──"
run_test "curl → no classifier matched" \
  "curl https://example.com" \
  "no classifier matched"

# ===== Custom pattern match =====
echo "── Custom pattern traces ──"
TEMP_DIR=$(mktemp -d)
TEMP_PATTERNS="$TEMP_DIR/command-permissions.json"
echo '{"allow":["my-custom-tool *"]}' >"$TEMP_PATTERNS"

label="custom pattern match"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  output=$(COMMAND_PERMISSIONS_GLOBAL="$TEMP_PATTERNS" \
    COMMAND_PERMISSIONS_PROJECT="/dev/null" \
    bash "$EXPLAIN_SCRIPT" "my-custom-tool --flag" 2>/dev/null) || true

  if echo "$output" | grep -qi "custom pattern" && echo "$output" | grep -qi "ALLOW"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  missing: custom pattern or ALLOW"
    ((FAIL++)) || true
  fi
fi
rm -rf "$TEMP_DIR"

# ===== Empty command =====
echo "── Edge cases ──"
label="empty command → usage message"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  output=$(bash "$EXPLAIN_SCRIPT" "" 2>/dev/null) || true
  output_no_arg=$(bash "$EXPLAIN_SCRIPT" 2>/dev/null) || true

  if echo "$output_no_arg" | grep -qi "usage"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  missing: usage"
    ((FAIL++)) || true
  fi
fi

# ===== Summary =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
if [[ $SKIP -gt 0 ]]; then
  printf "  \033[33m%d skipped\033[0m" "$SKIP"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
