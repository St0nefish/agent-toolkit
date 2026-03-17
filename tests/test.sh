#!/usr/bin/env bash
# Auto-discovery test runner — finds and runs all test-*.sh scripts under tests/*/.
# Reports per-suite results with pass/fail counts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITES=0
SUITE_FAILURES=0

for script in "$SCRIPT_DIR"/*/test-*.sh; do
  [[ -f "$script" ]] || continue
  suite=$(basename "$(dirname "$script")")
  name=$(basename "$script" .sh)
  SUITES=$((SUITES + 1))

  echo "=== $suite/$name ==="
  exit_code=0
  bash "$script" "$@" || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    SUITE_FAILURES=$((SUITE_FAILURES + 1))
    echo "  SUITE FAILED (exit $exit_code)"
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ran $SUITES suite(s), $SUITE_FAILURES failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$SUITE_FAILURES"
