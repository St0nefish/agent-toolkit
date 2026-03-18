#!/usr/bin/env bash
# lint-shell.sh — PostToolUse hook that runs shellcheck on edited shell scripts.
# Always exits 0 — never blocks Claude. Linter output goes to stderr.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ -f "$FILE" ]] || exit 0
[[ "$FILE" == *.sh || "$FILE" == *.bash ]] || exit 0

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "[lint-shell] WARN: shellcheck not found — skipping $FILE" >&2
  exit 0
fi

shellcheck "$FILE" >&2 || true
exit 0
