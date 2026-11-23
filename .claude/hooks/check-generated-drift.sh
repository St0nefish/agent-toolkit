#!/usr/bin/env bash
# check-generated-drift.sh — PreToolUse(Bash) hook: block `git commit` while a
# generated tree (vendored utils, opencode session port, skills catalog) is
# stale. Runs utils/regen-generated.sh --check; exit 2 blocks the call and
# feeds the message back to Claude.
#
# This exists because .githooks/pre-commit only runs when core.hooksPath is set
# to .githooks, and a global core.hooksPath silently disables it. A Claude Code
# project hook needs no per-clone setup.

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only commits. Matches `git commit` anywhere in the command line (so chained
# `git add … && git commit …` is caught), allowing global options between:
# bare flags (`--no-pager`, `-p`), `--git-dir=x`, and flag + value (`-C dir`).
# It is a plain text match, so a quoted `git commit` (an echo, a PR body) is a
# false positive while a tree is stale; the message says why.
[[ "$CMD" =~ (^|[^[:alnum:]_-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$) ]] || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -x "$ROOT/utils/regen-generated.sh" ]] || exit 0

if ! OUT=$("$ROOT/utils/regen-generated.sh" --check 2>&1); then
  {
    echo "[check-generated-drift] commit blocked: generated trees are out of date."
    echo "$OUT"
    echo "Run utils/regen-generated.sh, git add the regenerated files, then commit again."
  } >&2
  exit 2
fi
exit 0
