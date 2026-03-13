#!/usr/bin/env bash
# Setup/teardown helper for permission-manager integration tests.
# Usage:
#   test-integration.sh setup     — creates temp dir with fixtures + git repo, prints path
#   test-integration.sh teardown <path> — removes the temp dir
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

case "${1:-}" in
  setup)
    TD=$(mktemp -d /tmp/perm-test-XXXXXX)
    cp -r "$FIXTURES"/. "$TD/"
    git -C "$TD" init -b main >/dev/null 2>&1
    git -C "$TD" config user.email "test@test.local"
    git -C "$TD" config user.name "Test"
    git -C "$TD" add -A >/dev/null 2>&1
    git -C "$TD" commit -m "initial commit" >/dev/null 2>&1
    git -C "$TD" checkout -b feature-branch >/dev/null 2>&1
    git -C "$TD" tag v0.1.0 >/dev/null 2>&1
    git -C "$TD" checkout main >/dev/null 2>&1
    echo "$TD"
    ;;
  teardown)
    dir="${2:-}"
    if [[ "$dir" == /tmp/perm-test-* && -d "$dir" ]]; then
      rm -rf "$dir"
      echo "Cleaned up $dir"
    else
      echo "Invalid path: $dir" >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 {setup|teardown <path>}" >&2
    exit 1
    ;;
esac
