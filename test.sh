#!/usr/bin/env bash
# Run ALL tests across the repo.
# Usage: bash test.sh [filter-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

declare -a suites=()
declare -a suite_passed=()
declare -a suite_failed=()
declare -a suite_ok=()

# Parse pass/fail counts from captured output.
# Handles pytest ("N passed", "N failed") and bash ("PASS: N  FAIL: N" / individual PASS:/FAIL: lines).
count_results() {
    local file="$1"
    local passed=0 failed=0

    # pytest summary lines: "172 passed" / "3 failed"
    local py_passed py_failed
    py_passed=$(grep -oE '[0-9]+ passed' "$file" | awk '{s+=$1} END {print s+0}')
    py_failed=$(grep -oE '[0-9]+ failed' "$file" | awk '{s+=$1} END {print s+0}')
    passed=$((passed + py_passed))
    failed=$((failed + py_failed))

    # Bash test summary lines: "Total: 48  PASS: 48  FAIL: 0" or "PASSED: 37  FAILED: 0"
    local bash_passed bash_failed
    bash_passed=$(grep -oE '(PASS(ED)?): [0-9]+' "$file" | awk -F': ' '{s+=$2} END {print s+0}')
    bash_failed=$(grep -oE '(FAIL(ED)?): [0-9]+' "$file" | grep -v 'FAILED:.*test' | awk -F': ' '{s+=$2} END {print s+0}')
    passed=$((passed + bash_passed))
    failed=$((failed + bash_failed))

    # cargo test: "test result: ok. 5 passed; 0 failed;"
    local cargo_passed cargo_failed
    cargo_passed=$(grep -oE 'test result:.*[0-9]+ passed' "$file" | grep -oE '[0-9]+ passed' | awk '{s+=$1} END {print s+0}')
    cargo_failed=$(grep -oE 'test result:.*[0-9]+ failed' "$file" | grep -oE '[0-9]+ failed' | awk '{s+=$1} END {print s+0}')
    passed=$((passed + cargo_passed))
    failed=$((failed + cargo_failed))

    echo "$passed $failed"
}

run_suite() {
    local name="$1"; shift
    local outfile="$tmpdir/${name//\//-}.out"
    suites+=("$name")

    echo "==============================="
    echo "=== $name"
    echo "==============================="

    local exit_code=0
    "$@" 2>&1 | tee "$outfile" || exit_code=$?

    local counts
    counts=$(count_results "$outfile")
    local p=${counts%% *} f=${counts##* }
    suite_passed+=("$p")
    suite_failed+=("$f")

    if [ "$exit_code" -eq 0 ]; then
        suite_ok+=("PASS")
    else
        suite_ok+=("FAIL")
    fi
    echo ""
}

# Plugin tests (skills/hooks)
if [ -f tests/test.sh ]; then
    run_suite "plugins" bash tests/test.sh "$@"
fi

# Summary
echo "==============================="
echo "=== Summary"
echo "==============================="
total_passed=0 total_failed=0 any_failed=0
for i in "${!suites[@]}"; do
    p="${suite_passed[$i]}"
    f="${suite_failed[$i]}"
    status="${suite_ok[$i]}"
    printf "  %-20s %4d passed  %4d failed  [%s]\n" "${suites[$i]}" "$p" "$f" "$status"
    total_passed=$((total_passed + p))
    total_failed=$((total_failed + f))
    [ "$status" = "FAIL" ] && any_failed=1
done
echo "  ---"
printf "  %-20s %4d passed  %4d failed\n" "Total" "$total_passed" "$total_failed"
echo ""

if [ "$any_failed" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some suites failed."
fi

exit "$any_failed"
