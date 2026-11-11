#!/usr/bin/env bash
# test-inbox-core.sh — run the inbox core module's node unit tests.
# Requires a node that can import .ts directly (node >= 23 with type
# stripping). Skips with a note on older runtimes, mirroring the
# lint-shell.sh philosophy: hard in CI, warning locally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! node --version | grep -qE 'v(2[3-9]|[3-9][0-9])'; then
	if [[ -n "${CI:-}" ]]; then
		echo "node >= 23 required for TS type stripping and CI is set — refusing to skip" >&2
		exit 1
	fi
	echo "node >= 23 required — skipping inbox core tests" >&2
	exit 0
fi

exec node "$SCRIPT_DIR/test-inbox-core.mjs" "$@"
