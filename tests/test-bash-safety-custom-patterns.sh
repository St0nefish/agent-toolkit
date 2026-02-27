#!/usr/bin/env bash
# Tests for bash-safety custom command pattern matching.
# Run from repo root: bash tests/test-bash-safety-custom-patterns.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/plugins/permission-manager/scripts/bash-safety.sh"

PASS=0 FAIL=0

# Create temp dir for test config files
TEMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Set up global command-permissions.json
GLOBAL_CONFIG="$TEMP_DIR/global-command-permissions.json"
cat > "$GLOBAL_CONFIG" <<'EOF'
{
  "allow": [
    "pandoc *",
    "~/.claude/tools/session/bin/catchup *"
  ]
}
EOF

# Set up project command-permissions.json
PROJECT_CONFIG="$TEMP_DIR/project-command-permissions.json"
cat > "$PROJECT_CONFIG" <<'EOF'
{
  "allow": [
    "bash tests/test-*",
    "myctl status *"
  ]
}
EOF

# Export env vars so bash-safety.sh picks up our test configs
export COMMAND_PERMISSIONS_GLOBAL="$GLOBAL_CONFIG"
export COMMAND_PERMISSIONS_PROJECT="$PROJECT_CONFIG"

test_hook() {
  local label="$1" cmd="$2" expected="$3"
  local output json
  json=$(jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
  output=$(echo "$json" | bash "$HOOK" 2>/dev/null) || true
  local decision=""
  if echo "$output" | grep -q '"allow"'; then decision="allow"
  elif echo "$output" | grep -q '"ask"'; then decision="ask"
  elif echo "$output" | grep -q '"deny"'; then decision="deny"
  else decision="none"
  fi
  if [[ "$decision" == "$expected" ]]; then
    echo "PASS: $label → $decision"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label → got $decision, expected $expected"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Custom Pattern Tests ==="
echo ""

echo "--- Global patterns ---"
test_hook "global: pandoc matches" "pandoc README.md" "allow"
test_hook "global: pandoc multi-arg" "pandoc -f markdown -t html README.md" "allow"

echo ""
echo "--- Project patterns ---"
test_hook "project: test script matches" "bash tests/test-foo.sh" "allow"
test_hook "project: test script with args" "bash tests/test-hook.sh --verbose" "allow"
test_hook "project: myctl status" "myctl status --all" "allow"

echo ""
echo "--- No match falls through ---"
test_hook "no match: rm -rf" "rm -rf /" "ask"
test_hook "no match: curl" "curl http://example.com" "ask"

echo ""
echo "--- Exact non-match ---"
test_hook "no match: pandoc alone (no args)" "pandoc" "ask"
test_hook "no match: different prefix" "bash src/test-foo.sh" "ask"

echo ""
echo "--- Compound commands: custom + safe ---"
test_hook "compound: custom && read-only" "bash tests/test-foo.sh && echo done" "allow"

echo ""
echo "--- Compound commands: custom + write ---"
test_hook "compound: custom && git push" "bash tests/test-foo.sh && git push" "ask"

echo ""
echo "--- Compound commands: custom + deny ---"
test_hook "compound: custom + redirect" "bash tests/test-foo.sh > out.txt" "deny"

echo ""
echo "--- Project supplements global ---"
test_hook "both scopes: global pandoc" "pandoc --version foo" "allow"
test_hook "both scopes: project test" "bash tests/test-bar.sh" "allow"

echo ""
echo "--- No config files ---"
# Point to nonexistent files — should fall through to normal classifiers
COMMAND_PERMISSIONS_GLOBAL="/nonexistent/global.json" \
COMMAND_PERMISSIONS_PROJECT="/nonexistent/project.json" \
  test_hook "no config: ls still allowed" "ls -la" "allow"
COMMAND_PERMISSIONS_GLOBAL="/nonexistent/global.json" \
COMMAND_PERMISSIONS_PROJECT="/nonexistent/project.json" \
  test_hook "no config: git push still ask" "git push" "ask"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
