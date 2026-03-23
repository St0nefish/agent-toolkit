#!/usr/bin/env bash
# test-agent-definitions.sh — Validate .claude/agents/*.md structural correctness.
#
# Usage: bash tests/agents/test-agent-definitions.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/../../.claude/agents"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}

# Extract YAML frontmatter (between first pair of --- delimiters)
extract_frontmatter() {
  awk '/^---$/ { n++; next } n==1 { print } n>=2 { exit }' "$1"
}

# Extract tools list from frontmatter
extract_tools() {
  extract_frontmatter "$1" | awk '/^tools:/{found=1;next} found && /^  - /{print $2} found && !/^  - /{exit}'
}

# Get a frontmatter field value (simple scalar)
get_field() {
  extract_frontmatter "$1" | grep "^$2:" | head -1 | sed "s/^$2: *//"
}

# ---------------------------------------------------------------------------
# Test: agent frontmatter — required fields
# ---------------------------------------------------------------------------

echo "── agent frontmatter: required fields ──"

for agent_file in "$AGENTS_DIR"/*.md; do
  basename="$(basename "$agent_file")"

  if [[ -n "$FILTER" ]] && ! echo "$basename" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    continue
  fi

  # name
  name=$(get_field "$agent_file" "name")
  if [[ -n "$name" ]]; then
    pass "$basename — name present"
  else
    fail "$basename — name present" "missing"
  fi

  # description
  desc=$(get_field "$agent_file" "description")
  if [[ -n "$desc" ]]; then
    pass "$basename — description present"
  else
    fail "$basename — description present" "missing"
  fi

  # tools
  tools=$(extract_tools "$agent_file")
  if [[ -n "$tools" ]]; then
    pass "$basename — tools present"
  else
    fail "$basename — tools present" "missing or empty"
  fi
done

# ---------------------------------------------------------------------------
# Test: research agent — read-only tool whitelist
# ---------------------------------------------------------------------------

echo "── research agent: tool whitelist ──"

RESEARCH="$AGENTS_DIR/research.md"

if [[ ! -f "$RESEARCH" ]]; then
  fail "research.md exists" "file not found"
else
  tools=$(extract_tools "$RESEARCH")

  # Mutation tools must NOT be present
  for banned in Edit Write; do
    label="$banned not in tools list"
    if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
      ((SKIP++)) || true
      continue
    fi
    if echo "$tools" | grep -qx "$banned"; then
      fail "$label" "found $banned"
    else
      pass "$label"
    fi
  done

  # Required tools must be present
  for required in Read Glob Grep Bash WebFetch WebSearch; do
    label="$required in tools list"
    if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
      ((SKIP++)) || true
      continue
    fi
    if echo "$tools" | grep -qx "$required"; then
      pass "$label"
    else
      fail "$label" "not found"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Test: agent name consistency
# ---------------------------------------------------------------------------

echo "── agent name consistency ──"

for agent_file in "$AGENTS_DIR"/*.md; do
  basename="$(basename "$agent_file")"
  expected_name="${basename%.md}"
  label="$basename — name matches filename"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    continue
  fi

  name=$(get_field "$agent_file" "name")
  if [[ "$name" == "$expected_name" ]]; then
    pass "$label"
  else
    fail "$label" "name='$name' expected='$expected_name'"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
