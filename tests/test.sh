#!/usr/bin/env bash
# Run skill/hook tests: bash test scripts + pytest.
# Usage: bash tests/test.sh [pytest-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

failed=0

# Plugin pytest tests
shopt -s nullglob
pytest_files=("$SCRIPT_DIR"/test_*.py)
shopt -u nullglob
if [ ${#pytest_files[@]} -gt 0 ]; then
    echo "=== plugin pytest ==="
    if uv run --with "pytest,python-frontmatter" pytest "${pytest_files[@]}" "$@"; then
        echo ""
    else
        echo "FAILED: plugin pytest"
        echo ""
        failed=1
    fi
fi

# Plugin bash tests
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
