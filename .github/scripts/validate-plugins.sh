#!/usr/bin/env bash
# validate-plugins.sh — structural validation for the plugin marketplace repo.
#
# Checks:
#   1. JSON validity           — all .json files parse cleanly
#   2. plugin.json fields      — required fields present in every plugin.json
#   3. Claude hooks.json       — PascalCase events, "command" key, no top-level "version"
#   4. Copilot hooks.json      — camelCase events, "bash" key, top-level "version": 1
#   5. Plugin root variables   — correct ${..._PLUGIN_ROOT} per CLI variant
#   6. Hook script existence   — referenced scripts resolve to real files
#   7. Symlink integrity       — all symlinks in plugins-copilot/ resolve
#   8. Version sync            — copilot plugin.json version matches claude counterpart
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
done < <(find . -name '*.json' -not -path './.git/*' -not -path '*/.rumdl_cache/*' | sort)

# ---------------------------------------------------------------------------
# 2. plugin.json required fields
# ---------------------------------------------------------------------------
echo ""
echo "=== plugin.json required fields ==="
while IFS= read -r f; do
  missing=$(jq -r '
    [
      (if .name          | length == 0 then "name"          else empty end),
      (if .version       | length == 0 then "version"       else empty end),
      (if .description   | length == 0 then "description"   else empty end),
      (if (.author.name // "") | length == 0 then "author.name" else empty end)
    ] | join(", ")
  ' "$f")
  if [[ -z "$missing" ]]; then
    pass "$f"
  else
    fail "$f — missing: $missing"
  fi
done < <(find . -name 'plugin.json' -path '*/.claude-plugin/*' -not -path './.git/*' | sort)

# ---------------------------------------------------------------------------
# 3 & 4. hooks.json structure
# ---------------------------------------------------------------------------
echo ""
echo "=== hooks.json structure ==="

validate_claude_hooks() {
  local f="$1"
  # Must not have top-level "version"
  if jq -e 'has("version")' "$f" >/dev/null 2>&1; then
    fail "$f — Claude hooks.json must not have top-level \"version\""
    return
  fi
  # Events must be PascalCase (first char uppercase)
  bad_events=$(jq -r '.hooks | keys[] | select(test("^[a-z]"))' "$f" 2>/dev/null)
  if [[ -n "$bad_events" ]]; then
    fail "$f — non-PascalCase events: $bad_events"
    return
  fi
  # Hook entries must use "command" key (not "bash")
  has_bash=$(jq -r '[.hooks[][] | .hooks[]? // . | select(has("bash"))] | length' "$f" 2>/dev/null)
  if [[ "$has_bash" -gt 0 ]]; then
    fail "$f — Claude hooks must use \"command\" key, not \"bash\""
    return
  fi
  pass "$f"
}

validate_copilot_hooks() {
  local f="$1"
  # Must have top-level "version": 1
  ver=$(jq -r '.version // empty' "$f" 2>/dev/null)
  if [[ "$ver" != "1" ]]; then
    fail "$f — Copilot hooks.json must have \"version\": 1"
    return
  fi
  # Events must be camelCase (first char lowercase)
  bad_events=$(jq -r '.hooks | keys[] | select(test("^[A-Z]"))' "$f" 2>/dev/null)
  if [[ -n "$bad_events" ]]; then
    fail "$f — non-camelCase events: $bad_events"
    return
  fi
  # Hook entries must use "bash" key
  has_command=$(jq -r '[.hooks[][] | select(has("command"))] | length' "$f" 2>/dev/null)
  if [[ "$has_command" -gt 0 ]]; then
    fail "$f — Copilot hooks must use \"bash\" key, not \"command\""
    return
  fi
  pass "$f"
}

while IFS= read -r f; do
  if [[ "$f" == *plugins-claude* ]]; then
    validate_claude_hooks "$f"
  elif [[ "$f" == *plugins-copilot* ]]; then
    validate_copilot_hooks "$f"
  fi
done < <(find . -name 'hooks.json' -path '*/hooks/*' -not -path './.git/*' | sort)

# ---------------------------------------------------------------------------
# 5. Plugin root variables
# ---------------------------------------------------------------------------
echo ""
echo "=== Plugin root variable correctness ==="
while IFS= read -r f; do
  if [[ "$f" == *plugins-claude* ]]; then
    if grep -q 'COPILOT_PLUGIN_ROOT' "$f"; then
      fail "$f — Claude hook references \${COPILOT_PLUGIN_ROOT}"
    else
      pass "$f"
    fi
  elif [[ "$f" == *plugins-copilot* ]]; then
    if grep -q 'CLAUDE_PLUGIN_ROOT' "$f"; then
      fail "$f — Copilot hook references \${CLAUDE_PLUGIN_ROOT}"
    else
      pass "$f"
    fi
  fi
done < <(find . -name 'hooks.json' -path '*/hooks/*' -not -path './.git/*' | sort)

# ---------------------------------------------------------------------------
# 6. Hook script existence
# ---------------------------------------------------------------------------
echo ""
echo "=== Hook script existence ==="
while IFS= read -r f; do
  plugin_root=$(dirname "$(dirname "$f")")
  # Extract command/bash values and resolve paths
  jq -r '
    .hooks[][] |
    (.hooks[]? // .) |
    (.command // .bash // empty)
  ' "$f" 2>/dev/null | while IFS= read -r cmd; do
    # Replace plugin root variable with actual path
    resolved=$(echo "$cmd" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$plugin_root|g; s|\${COPILOT_PLUGIN_ROOT}|$plugin_root|g")
    # Extract the script path (second token if starts with bash/sh, otherwise first)
    script_path=$(echo "$resolved" | awk '{if ($1 == "bash" || $1 == "sh") print $2; else print $1}')
    if [[ -f "$script_path" ]]; then
      pass "$f → $script_path"
    else
      fail "$f → $script_path not found"
    fi
  done
done < <(find . -name 'hooks.json' -path '*/hooks/*' -not -path './.git/*' | sort)

# ---------------------------------------------------------------------------
# 7. Symlink integrity
# ---------------------------------------------------------------------------
echo ""
echo "=== Symlink integrity ==="
while IFS= read -r link; do
  if [[ -e "$link" ]]; then
    pass "$link"
  else
    fail "$link → broken symlink (target: $(readlink "$link"))"
  fi
done < <(find ./plugins-copilot -type l 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# 8. Version sync (claude vs copilot)
# ---------------------------------------------------------------------------
echo ""
echo "=== Version sync (claude ↔ copilot) ==="
for claude_pj in ./plugins-claude/*/.claude-plugin/plugin.json; do
  plugin_name=$(jq -r '.name' "$claude_pj")
  copilot_pj="./plugins-copilot/$plugin_name/.claude-plugin/plugin.json"
  [[ -f "$copilot_pj" ]] || continue
  claude_ver=$(jq -r '.version' "$claude_pj")
  copilot_ver=$(jq -r '.version' "$copilot_pj")
  if [[ "$claude_ver" == "$copilot_ver" ]]; then
    pass "$plugin_name — $claude_ver"
  else
    fail "$plugin_name — claude=$claude_ver copilot=$copilot_ver"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "$CHECKS checks, $ERRORS failures"
exit "$([[ "$ERRORS" -eq 0 ]] && echo 0 || echo 1)"
