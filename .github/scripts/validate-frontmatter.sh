#!/usr/bin/env bash
# validate-frontmatter.sh — YAML frontmatter schema validation for commands and skills.
#
# Rules:
#   - Commands: "description" required
#   - Skills: "description" and "name" required
#   - If "user-invocable" present, must be "true" or "false"
#   - If "disable-model-invocation" present, must be "true" or "false"
#
# Exit codes: 0 = all passed, 1 = one or more failures.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

ERRORS=0
CHECKS=0

pass() {
  CHECKS=$((CHECKS + 1))
  echo "  ✓ $1"
}
fail() {
  CHECKS=$((CHECKS + 1))
  ERRORS=$((ERRORS + 1))
  echo "  ✗ $1" >&2
}

# Extract YAML frontmatter (content between first and second ---)
extract_frontmatter() {
  awk '/^---$/ { n++; next } n==1 { print } n>=2 { exit }' "$1"
}

# Check a boolean field: if present, must be "true" or "false"
check_bool_field() {
  local fm="$1" field="$2" file="$3"
  local value
  value=$(echo "$fm" | { grep "^${field}:" || true; } | head -1 | sed "s/^${field}:[[:space:]]*//" | tr -d '"' | tr -d "'")
  if [[ -n "$value" && "$value" != "true" && "$value" != "false" ]]; then
    fail "$file — $field must be true or false (got: $value)"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
echo "=== Command frontmatter ==="
while IFS= read -r f; do
  # Skip symlinks (avoid double-checking)
  [[ -L "$f" ]] && continue

  fm=$(extract_frontmatter "$f")
  if [[ -z "$fm" ]]; then
    fail "$f — no frontmatter found"
    continue
  fi

  # description required
  if echo "$fm" | grep -q "^description:"; then
    pass "$f — description present"
  else
    fail "$f — missing required field: description"
  fi

  # boolean field checks
  check_bool_field "$fm" "user-invocable" "$f"
  check_bool_field "$fm" "disable-model-invocation" "$f"
done < <(find ./plugins-claude ./plugins-copilot -path '*/commands/*.md' -type f 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
echo ""
echo "=== Skill frontmatter ==="
while IFS= read -r f; do
  # Skip symlinks
  [[ -L "$f" ]] && continue

  fm=$(extract_frontmatter "$f")
  if [[ -z "$fm" ]]; then
    fail "$f — no frontmatter found"
    continue
  fi

  # name required
  if echo "$fm" | grep -q "^name:"; then
    pass "$f — name present"
  else
    fail "$f — missing required field: name"
  fi

  # description required
  if echo "$fm" | grep -q "^description:"; then
    pass "$f — description present"
  else
    fail "$f — missing required field: description"
  fi

  # boolean field checks
  check_bool_field "$fm" "user-invocable" "$f"
  check_bool_field "$fm" "disable-model-invocation" "$f"
done < <(find ./plugins-claude ./plugins-copilot -path '*/skills/*/SKILL.md' -type f 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "$CHECKS checks, $ERRORS failures"
exit "$([[ "$ERRORS" -eq 0 ]] && echo 0 || echo 1)"
