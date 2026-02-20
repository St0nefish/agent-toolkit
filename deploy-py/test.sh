#!/usr/bin/env bash
# Run deploy-py pytest suite.
# Usage: bash deploy-py/test.sh [pytest-args...]
set -euo pipefail

if ! command -v uv &>/dev/null; then
  echo "Error: uv not found. Install via: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
uv run --directory "$SCRIPT_DIR" pytest "$SCRIPT_DIR/tests/" "$@"
