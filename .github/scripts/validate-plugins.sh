#!/usr/bin/env bash
# validate-plugins.sh — structural validation for the plugin marketplace repo.
#
# Checks:
#   1. JSON validity           — all .json files parse cleanly
#   2. plugin.json fields      — required fields present in every plugin.json
#   3. Marketplace coverage    — every plugin dir is listed in the matching marketplace with the expected source path
#   4. Claude hooks.json       — PascalCase events, "command" key, no top-level "version"
#   5. Copilot hooks.json      — camelCase event keys, "bash" key, top-level "version": 1
#   6. Plugin root variables   — correct ${..._PLUGIN_ROOT} per CLI variant
#   7. Hook script existence   — referenced scripts resolve to real files
#   8. Copilot docs paths      — Copilot commands/skills do not reference ${COPILOT_PLUGIN_ROOT}
#   9. Script auto-approval    — Copilot plugins with scripts register approve-own-scripts.sh
#  10. Compose assets          — docker-compose-backed setup scripts have docker-compose.yml beside them
#  11. Symlink integrity       — all symlinks in plugins-copilot/ resolve
#  12. Version sync            — copilot plugin.json version matches claude counterpart
#  13. Vendored utils drift    — plugins-claude/*/scripts/ copies match utils/
#  14. Extension entrypoints   — copilot-extensions/* contain loadable .mjs files and avoid console.log
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
# 3. Marketplace coverage
# ---------------------------------------------------------------------------
echo ""
echo "=== Marketplace coverage ==="

validate_marketplace_entries() {
  local marketplace="$1" plugin_root_prefix="$2" plugin_dirs_root="$3"
  while IFS= read -r plugin_root; do
    local plugin_json plugin_name expected_source actual_source
    plugin_json="$plugin_root/.claude-plugin/plugin.json"
    [[ -f "$plugin_json" ]] || continue
    plugin_name=$(jq -r '.name' "$plugin_json")
    expected_source="$plugin_root_prefix/$plugin_name"
    actual_source=$(jq -r --arg n "$plugin_name" '.plugins[] | select(.name == $n) | .source' "$marketplace" 2>/dev/null)

    if [[ -z "$actual_source" ]]; then
      fail "$marketplace — missing plugin entry for $plugin_name"
    elif [[ "$actual_source" != "$expected_source" ]]; then
      fail "$marketplace — $plugin_name source is $actual_source (expected $expected_source)"
    else
      pass "$marketplace — $plugin_name"
    fi
  done < <(find "$plugin_dirs_root" -mindepth 1 -maxdepth 1 -type d | sort)
}

validate_marketplace_entries "./.claude-plugin/marketplace.json" "./plugins-claude" "./plugins-claude"
validate_marketplace_entries "./.github/plugin/marketplace.json" "./plugins-copilot" "./plugins-copilot"

# ---------------------------------------------------------------------------
# 4 & 5. hooks.json structure
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
  # Hook entries must use the wrapped Claude shape:
  # .hooks.Event[] => { hooks: [{ type: "command", command: "..." }], matcher?: "..." }
  bad_shape=$(jq -r '
    [
      .hooks[] | .[] |
      select(((.hooks | type) != "array"))
    ] | length
  ' "$f" 2>/dev/null)
  if [[ "${bad_shape:-0}" -gt 0 ]]; then
    fail "$f — Claude hooks must use wrapped entries with hooks[] arrays"
    return
  fi
  bad_inner=$(jq -r '
    [
      .hooks[] | .[] | .hooks[] |
      select((.type // "") != "command" or ((.command // "") | length == 0))
    ] | length
  ' "$f" 2>/dev/null)
  if [[ "${bad_inner:-0}" -gt 0 ]]; then
    fail "$f — Claude hooks must contain command hook entries with type=command"
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

  # Copilot hooks must use the object shape:
  #   {"hooks": {"preToolUse": [{"bash": "..."}]}}
  local shape
  shape=$(jq -r '.hooks | type' "$f" 2>/dev/null)
  if [[ "$shape" != "object" ]]; then
    fail "$f — Copilot hooks.json must use object .hooks entries"
    return
  fi

  local bad_events has_command missing_bash
  bad_events=$(jq -r '.hooks | keys[] | select(test("^[A-Z]"))' "$f" 2>/dev/null)
  has_command=$(jq -r '[.hooks[]?[]? | objects | select(has("command"))] | length' "$f" 2>/dev/null)
  missing_bash=$(jq -r '[.hooks[]?[]? | objects | select(((.bash // "") | length) == 0)] | length' "$f" 2>/dev/null)

  if [[ -n "$bad_events" ]]; then
    fail "$f — non-camelCase events: $bad_events"
    return
  fi
  if [[ "${has_command:-0}" -gt 0 ]]; then
    fail "$f — Copilot hooks must use \"bash\" key, not \"command\""
    return
  fi
  if [[ "${missing_bash:-0}" -gt 0 ]]; then
    fail "$f — Copilot hooks must provide a non-empty \"bash\" command"
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
# 6. Plugin root variables
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
# 7. Hook script existence
# ---------------------------------------------------------------------------
echo ""
echo "=== Hook script existence ==="
while IFS= read -r f; do
  plugin_root=$(dirname "$(dirname "$f")")
  # Extract command/bash values and resolve paths.
  # Handles three shapes:
  #   Claude:            .hooks.EventName[].hooks[].command
  #   Copilot (object):  .hooks.eventName[].bash
  #   Copilot (array):   .hooks[].bash
  jq -r '
    if (.hooks | type) == "array" then
      .hooks[] | .bash // .command // empty
    else
      .hooks[] | .[] | (.hooks[]? // .) | .command // .bash // empty
    end
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
# 8. Copilot docs avoid plugin-root paths
# ---------------------------------------------------------------------------
echo ""
echo "=== Copilot docs avoid plugin-root paths ==="
while IFS= read -r f; do
  if grep -Fq '${COPILOT_PLUGIN_ROOT}' "$f"; then
    fail "$f — Copilot command/skill docs must not reference \${COPILOT_PLUGIN_ROOT}"
  else
    pass "$f"
  fi
done < <(find ./plugins-copilot \( -path '*/commands/*.md' -o -path '*/skills/*/SKILL.md' \) -type f | sort)

# ---------------------------------------------------------------------------
# 9. Copilot script auto-approval
# ---------------------------------------------------------------------------
echo ""
echo "=== Copilot script auto-approval ==="
while IFS= read -r plugin_root; do
  scripts_dir="$plugin_root/scripts"
  hooks_file="$plugin_root/hooks/hooks.json"

  [[ -d "$scripts_dir" ]] || continue

  shopt -s nullglob dotglob
  script_entries=("$scripts_dir"/*)
  shopt -u nullglob dotglob
  [[ ${#script_entries[@]} -gt 0 ]] || continue

  if [[ ! -f "$hooks_file" ]]; then
    fail "$plugin_root — scripts/ exists but hooks/hooks.json is missing"
    continue
  fi

  if grep -Fq 'approve-own-scripts.sh' "$hooks_file"; then
    pass "$plugin_root"
  else
    fail "$plugin_root — scripts/ exists but hooks.json does not register approve-own-scripts.sh"
  fi
done < <(find ./plugins-copilot -mindepth 1 -maxdepth 1 -type d | sort)

# ---------------------------------------------------------------------------
# 10. Compose assets
# ---------------------------------------------------------------------------
echo ""
echo "=== Compose assets ==="
while IFS= read -r setup_script; do
  plugin_root=$(dirname "$(dirname "$setup_script")")
  if grep -Fq 'docker compose' "$setup_script"; then
    if [[ -f "$plugin_root/docker-compose.yml" ]]; then
      pass "$plugin_root"
    else
      fail "$plugin_root — setup script uses docker compose but docker-compose.yml is missing"
    fi
  fi
done < <(find ./plugins-claude ./plugins-copilot -path '*/scripts/setup.sh' -type f | sort)

# ---------------------------------------------------------------------------
# 11. Symlink integrity
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
# 12. Version sync (claude vs copilot)
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
# 13. Vendored utils drift
# ---------------------------------------------------------------------------
echo ""
echo "=== Vendored utils drift ==="
if bash utils/sync.sh --check 2>&1; then
  pass "utils/ copies match plugins-claude/*/scripts/"
else
  fail "vendored utils drifted — run utils/sync.sh and commit"
fi

# ---------------------------------------------------------------------------
# 14. Extension entrypoints
# ---------------------------------------------------------------------------
echo ""
echo "=== Extension entrypoints ==="
while IFS= read -r ext_dir; do
  ext_entry="$ext_dir/extension.mjs"
  if [[ -f "$ext_entry" ]]; then
    pass "$ext_entry"
  else
    fail "$ext_dir — missing extension.mjs"
    continue
  fi

  while IFS= read -r mjs; do
    if node --check "$mjs" >/dev/null 2>&1; then
      pass "$mjs — syntax ok"
    else
      fail "$mjs — syntax error"
    fi

    if grep -q 'console\.log' "$mjs"; then
      fail "$mjs — use session.log() instead of console.log()"
    else
      pass "$mjs — no console.log"
    fi
  done < <(find "$ext_dir" -type f -name '*.mjs' | sort)
done < <(find ./copilot-extensions -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "$CHECKS checks, $ERRORS failures"
exit "$([[ "$ERRORS" -eq 0 ]] && echo 0 || echo 1)"
