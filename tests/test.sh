#!/usr/bin/env bash
# Run skill/hook tests: bash test scripts + pytest.
# Usage: bash tests/test.sh [pytest-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

failed=0

# Skill/hook pytest tests
shopt -s nullglob
pytest_files=("$SCRIPT_DIR"/test_*.py)
shopt -u nullglob
if [ ${#pytest_files[@]} -gt 0 ]; then
    echo "=== skill/hook pytest ==="
    if uv run --directory deploy-py pytest "${pytest_files[@]}" "$@"; then
        echo ""
    else
        echo "FAILED: skill/hook pytest"
        echo ""
        failed=1
    fi
fi

# Skill/hook bash tests
for t in "$SCRIPT_DIR"/test-*.sh; do
    [ -e "$t" ] || continue
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
