#!/usr/bin/env bash
# lint-markdown.sh — PostToolUse hook that runs rumdl on edited markdown files.
# Always exits 0 — never blocks Claude. Linter output goes to stderr.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -n "$FILE" ]] || exit 0
[[ -f "$FILE" ]] || exit 0
[[ "$FILE" == *.md ]] || exit 0

if ! command -v rumdl >/dev/null 2>&1; then
  echo "[lint-markdown] WARN: rumdl not found — skipping $FILE" >&2
  exit 0
fi

rumdl "$FILE" >&2 || true
exit 0
