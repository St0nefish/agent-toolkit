#!/usr/bin/env bash
# Run all tests: pytest + bash test scripts.
# Usage: bash tests/run-all.sh [pytest-args...]
#
# Examples:
#   bash tests/run-all.sh              # all tests
#   bash tests/run-all.sh -v           # verbose pytest
#   bash tests/run-all.sh -k perms     # filter pytest by name
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

failed=0

echo "=== pytest ==="
if uv run pytest tests/ "$@"; then
    echo ""
else
    echo "FAILED: pytest"
    echo ""
    failed=1
fi

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

if [ "$failed" -eq 0 ]; then
    echo "All tests passed."
fi

exit "$failed"
