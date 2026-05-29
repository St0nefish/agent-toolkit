#!/usr/bin/env bash
#
# test-command-docs.sh — Checks that Copilot-facing sf-code-review command docs
# encode the intended scope flags and Opus guardrails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../../plugins-copilot/sf-code-review"

PASS=0
FAIL=0

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (missing: %s)\n" "$label" "$needle"
    ((FAIL++)) || true
  fi
}

echo "── command docs include expected arguments and routing ──"

COMMAND_DOC=$(cat "$PLUGIN_DIR/commands/review.md")

assert_contains "command routes to sibling skill" 'invokes the `sf-code-review` skill' "$COMMAND_DOC"
assert_contains "argument hint includes --base" '--base <ref>' "$COMMAND_DOC"
assert_contains "argument hint includes --staged" '--staged' "$COMMAND_DOC"
assert_contains "argument hint includes --scope" '--scope <path> ...' "$COMMAND_DOC"
assert_contains "argument hint includes --focus" '--focus "' "$COMMAND_DOC"
assert_contains "argument hint includes --exception" '--exception "' "$COMMAND_DOC"

echo "── command docs encode model pipeline and Opus guardrails ──"

assert_contains "command mentions Sonnet reviewer" 'Claude Sonnet 4.6' "$COMMAND_DOC"
assert_contains "command mentions GPT reviewer" 'GPT-5.4' "$COMMAND_DOC"
assert_contains "command mentions Opus adjudicator" 'Claude Opus 4.6' "$COMMAND_DOC"
assert_contains "command says Opus is adjudicator" 'Opus is an adjudicator, not a third reviewer.' "$COMMAND_DOC"
assert_contains "command skips Opus when no candidates" 'If no reviewer flags a candidate issue and there is no disagreement, skip Opus.' "$COMMAND_DOC"
assert_contains "command forbids full diff to Opus" 'Never pass the full diff to Opus unless a candidate cannot be understood otherwise.' "$COMMAND_DOC"
assert_contains "command pins Opus to 4.6 only" 'use **only** `claude-opus-4.6` — never `claude-opus-4.7` or `claude-opus-4.8`.' "$COMMAND_DOC"
assert_contains "command preserves freeform context" 'preserve it as additional' "$COMMAND_DOC"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
