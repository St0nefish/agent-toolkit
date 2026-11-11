#!/usr/bin/env bash
# test-session-core.sh — run the session orchestrate-core node unit tests.
# Requires a node that can import .ts directly (node >= 23 with type
# stripping). Skips with a note on older runtimes, mirroring
# test-inbox-core.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! node --version | grep -qE 'v(2[3-9]|[3-9][0-9])'; then
	if [[ -n "${CI:-}" ]]; then
		echo "node >= 23 required for TS type stripping and CI is set — refusing to skip" >&2
		exit 1
	fi
	echo "node >= 23 required — skipping session core tests" >&2
	exit 0
fi

exec node "$SCRIPT_DIR/test-session-core.mjs" "$@"
