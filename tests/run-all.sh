#!/usr/bin/env bash
# Run all test scripts in the tests/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

for t in "$SCRIPT_DIR"/test-*.sh; do
    echo "=== $(basename "$t") ==="
    if bash "$t"; then
        echo ""
    else
        echo "FAILED: $(basename "$t")"
        echo ""
        failed=1
    fi
done

exit "$failed"
