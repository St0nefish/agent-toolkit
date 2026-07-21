#!/usr/bin/env bash
# test-wwcut.sh — run the wwcut cut-list optimizer unit tests.
#
# wwcut is pure Python (no FreeCAD import), so this just runs the Python test
# module under whatever python3 is on PATH. Discovered and run by tests/test.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec python3 "$SCRIPT_DIR/test_wwcut.py"
