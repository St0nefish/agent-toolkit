#!/usr/bin/env bash
# validate-opencode.sh — structural validation for the plugins-opencode/ tree.
#
# Deliberately separate from validate-plugins.sh: those checks are
# Claude/Copilot-specific (hooks.json casing, _PLUGIN_ROOT vars, marketplace
# files) and none of those artifacts exist for OpenCode.
#
# Checks:
#   1. JSON validity        — all .json files under plugins-opencode parse
#   2. JSONC snippets       — config snippets parse after stripping line comments
#   3. Code plugin packages — inbox/session carry a package.json whose exports
#                              point at files that exist
#   4. Skill frontmatter    — SKILL.md files have name and description
#   5. Command bodies       — command .md files have a non-empty body
#   6. No Claude leakage    — no ${CLAUDE_PLUGIN_ROOT}/${CLAUDE_SESSION_ID} refs
#   7. Vendored scripts     — plugins-opencode/*/scripts/* are executable
#   8. Skills catalog       — skills-catalog/ (HTTP catalog for machines
#                             without a checkout) matches the skill sources
#
# Exit codes: 0 = all passed, 1 = one or more failures.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

TARGET="plugins-opencode"
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

# ---------------------------------------------------------------------------
# 1. JSON validity
# ---------------------------------------------------------------------------
echo "=== JSON validity ==="
while IFS= read -r f; do
  if jq empty "$f" 2>/dev/null; then
    pass "$f"
  else
    fail "$f — invalid JSON"
  fi
done < <(find "$TARGET" -name '*.json' -type f | sort)

# ---------------------------------------------------------------------------
# 2. JSONC config snippets
# ---------------------------------------------------------------------------
echo ""
echo "=== JSONC snippet validity ==="
while IFS= read -r f; do
  # Strip full-line // comments and trailing commas, then parse with node
  # (CI runners have it; this is a syntax gate only, not a schema check).
  if node -e '
		const s = require("fs").readFileSync(process.argv[1], "utf8")
			.replace(/^\s*\/\/.*$/gm, "")
			.replace(/,(\s*[}\]])/g, "$1");
		JSON.parse(s);
	' "$f" 2>/dev/null; then
    pass "$f"
  else
    fail "$f — invalid JSONC"
  fi
done < <(find "$TARGET" -name '*.jsonc' -type f | sort)

# ---------------------------------------------------------------------------
# 3. Code plugin packages
# ---------------------------------------------------------------------------
echo ""
echo "=== Code plugin packages ==="
for plugin in inbox session; do
  pj="$TARGET/$plugin/package.json"
  if [[ ! -f "$pj" ]]; then
    fail "$pj missing (behavioral plugins ship a package.json)"
    continue
  fi
  name=$(jq -r '.name // empty' "$pj")
  type_=$(jq -r '.type // empty' "$pj")
  if [[ -z "$name" ]]; then
    fail "$pj — missing name"
  elif [[ "$type_" != "module" ]]; then
    fail "$pj — type must be \"module\" (got: ${type_:-missing})"
  else
    pass "$pj — name=$name type=module"
  fi
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    if [[ -f "$TARGET/$plugin/${target#./}" ]]; then
      pass "$plugin export → $target"
    else
      fail "$plugin export target missing: $target"
    fi
  done < <(jq -r '.exports[]? // empty' "$pj")
done

# ---------------------------------------------------------------------------
# 4. Skill frontmatter
# ---------------------------------------------------------------------------
echo ""
echo "=== Skill frontmatter ==="
while IFS= read -r f; do
  fm=$(awk '/^---$/ { n++; next } n==1 { print } n>=2 { exit }' "$f")
  if [[ -z "$fm" ]]; then
    fail "$f — no frontmatter found"
    continue
  fi
  ok=1
  for field in name description; do
    if ! echo "$fm" | grep -q "^${field}:"; then
      fail "$f — missing required field: $field"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && pass "$f"
done < <(find "$TARGET" -path '*/skills/*/SKILL.md' -type f | sort)

# ---------------------------------------------------------------------------
# 5. Command bodies
# ---------------------------------------------------------------------------
echo ""
echo "=== Command bodies ==="
while IFS= read -r f; do
  body=$(awk '/^---$/{n++; next} n>=2' "$f" | sed '/./,$!d')
  if [[ -n "$body" ]]; then
    pass "$f"
  else
    fail "$f — empty command body (the body is the prompt template)"
  fi
done < <(find "$TARGET" -path '*/commands/*.md' -type f | sort)

# ---------------------------------------------------------------------------
# 6. No Claude harness leakage
# ---------------------------------------------------------------------------
echo ""
echo "=== No Claude harness leakage ==="
if hits=$(grep -rn 'CLAUDE_PLUGIN_ROOT\|CLAUDE_SESSION_ID' "$TARGET" 2>/dev/null); then
  while IFS= read -r line; do
    fail "Claude var in OpenCode tree: $line"
  done <<<"$hits"
else
  pass "no \${CLAUDE_*} vars under $TARGET"
fi

# ---------------------------------------------------------------------------
# 7. Vendored scripts executable
# ---------------------------------------------------------------------------
echo ""
echo "=== Vendored scripts executable ==="
while IFS= read -r f; do
  if [[ -x "$f" ]]; then
    pass "$f"
  else
    fail "$f — not executable"
  fi
done < <(find "$TARGET" -path '*/scripts/*' -type f | sort)

# ---------------------------------------------------------------------------
# 8. Skills catalog up to date
# ---------------------------------------------------------------------------
echo ""
echo "=== Skills catalog ==="
if [[ ! -f utils/skills-catalog.py ]]; then
  # Fixture trees built by tests/opencode/test-validate-opencode.sh carry a
  # minimal plugins-opencode/ with no generator; the real gate on the
  # generator itself lives in tests/opencode/test-skills-catalog.sh.
  pass "skills-catalog generator absent — nothing to check"
elif python3 utils/skills-catalog.py --check; then
  pass "skills-catalog/ matches the skill sources"
else
  fail "skills-catalog/ is stale — run utils/skills-catalog.py"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "$CHECKS checks, $ERRORS failures"
exit "$([[ "$ERRORS" -eq 0 ]] && echo 0 || echo 1)"
