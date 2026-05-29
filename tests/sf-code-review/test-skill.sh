#!/usr/bin/env bash
# test-skill.sh — Tests for the sf-code-review orchestration skill.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../../plugins-copilot/sf-code-review/skills/sf-code-review/SKILL.md"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n    expected: %s\n    got:      %s\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (missing: %s)\n" "$label" "$needle"
    ((FAIL++)) || true
  fi
}

echo "── skill frontmatter ──"

FRONTMATTER=$(awk '/^---$/{count++; if(count==2) exit} count==1' "$SKILL_FILE")
SKILL_CONTENT=$(cat "$SKILL_FILE")

assert_eq "name field" "sf-code-review" \
  "$(echo "$FRONTMATTER" | grep '^name:' | awk '{print $2}')"
assert_eq "user-invocable false" "false" \
  "$(echo "$FRONTMATTER" | grep '^user-invocable:' | awk '{print $2}')"
assert_contains "allowed-tools includes Bash" 'Bash' "$FRONTMATTER"
assert_contains "allowed-tools includes Read" 'Read' "$FRONTMATTER"
assert_contains "allowed-tools includes AskUserQuestion" 'AskUserQuestion' "$FRONTMATTER"
assert_contains "allowed-tools includes Task" 'Task' "$FRONTMATTER"
assert_contains "description mentions dual review" 'dual' "$FRONTMATTER"

echo "── trigger and scope guidance ──"

assert_contains "trigger: extensive code review" 'extensive code review' "$SKILL_CONTENT"
assert_contains "trigger: split into chunks" 'split the review into chunks' "$SKILL_CONTENT"
assert_contains "trigger: dual review" 'dual review' "$SKILL_CONTENT"
assert_contains "mentions staged precedence" 'review `git diff --cached` and ignore `--base`' "$SKILL_CONTENT"
assert_contains "mentions semantic chunking" 'semantic unit first' "$SKILL_CONTENT"
assert_contains "mentions chunk cap" 'at most `6` chunks' "$SKILL_CONTENT"
assert_contains "mentions phase prompt for large scope" 'review in phases' "$SKILL_CONTENT"

echo "── baseline review and cross-cutting sweep guardrails ──"

assert_contains "focus adds to baseline" 'Custom focus areas add to the baseline.' "$SKILL_CONTENT"
assert_contains "exceptions are narrow" 'Exceptions are narrow.' "$SKILL_CONTENT"
assert_contains "cross-cutting checklist includes schema drift" 'interface / schema drift' "$SKILL_CONTENT"
assert_contains "cross-cutting checklist includes call-site mismatch" 'call-site mismatch across files' "$SKILL_CONTENT"
assert_contains "cross-cutting checklist includes config compatibility" 'config or migration compatibility' "$SKILL_CONTENT"
assert_contains "cross-cutting sweep not full review" 'Do not use this pass as a second full review.' "$SKILL_CONTENT"

echo "── reviewer schema and Opus adjudication guardrails ──"

assert_contains "strict finding schema required" 'strict finding schema' "$SKILL_CONTENT"
assert_contains "reviewer NO_FINDINGS sentinel" 'NO_FINDINGS' "$SKILL_CONTENT"
assert_contains "finding schema includes finding_id" 'finding_id:' "$SKILL_CONTENT"
assert_contains "finding schema includes minimal_evidence" 'minimal_evidence:' "$SKILL_CONTENT"
assert_contains "finding schema includes suggested_check" 'suggested_check:' "$SKILL_CONTENT"
assert_contains "mentions Sonnet model" 'claude-sonnet-4.6' "$SKILL_CONTENT"
assert_contains "mentions GPT model" 'gpt-5.4' "$SKILL_CONTENT"
assert_contains "mentions Opus model" 'claude-opus-4.6' "$SKILL_CONTENT"
assert_contains "forbids Opus 4.7" 'Never substitute `claude-opus-4.7`' "$SKILL_CONTENT"
assert_contains "forbids Opus 4.8" '`claude-opus-4.8`' "$SKILL_CONTENT"
assert_contains "Opus is adjudicator" 'you are an adjudicator, not a third reviewer' "$SKILL_CONTENT"
assert_contains "skip Opus when no candidates" 'If no reviewer flags a candidate finding and there is no disagreement, skip Opus.' "$SKILL_CONTENT"
assert_contains "forbid net-new findings" 'Opus must not introduce net-new unrelated findings.' "$SKILL_CONTENT"
assert_contains "require confirmed rejected uncertain verdicts" 'verdict: confirmed|rejected|uncertain' "$SKILL_CONTENT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
