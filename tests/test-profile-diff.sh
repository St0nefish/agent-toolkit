#!/usr/bin/env bash
# Tests for .claude/skills/deploy/bin/profile-diff
# Run from repo root: bash tests/test-profile-diff.sh
#
# profile-diff reads discover JSON from stdin and takes a profile path as its
# sole argument. It outputs a JSON object:
#   {"added": {"skills": [...], "hooks": [...], "mcp": [...]},
#    "removed": {"skills": [...], "hooks": [...], "mcp": [...]}}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_DIFF="$REPO_DIR/.claude/skills/deploy/bin/profile-diff"

PASS=0 FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

# Sanity check
if [[ ! -f "$PROFILE_DIFF" ]]; then
    echo "ERROR: profile-diff not found at $PROFILE_DIFF" >&2
    exit 1
fi

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT
echo "Using TESTDIR=$TESTDIR"

# Helper: run profile-diff with a JSON discover payload and a profile file path.
# Writes result to stdout; caller captures it.
# Usage: run_profile_diff <profile_path> <discover_json_string>
run_profile_diff() {
    local profile_path="$1"
    local discover_json="$2"
    printf '%s' "$discover_json" | python3 "$PROFILE_DIFF" "$profile_path"
}

# ---------------------------------------------------------------------------
# Test 1: No drift — all items match
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 1: No drift ==="
profile1="$TESTDIR/profile1.json"
cat > "$profile1" << 'EOF'
{
  "skills": {"foo": {"enabled": true}, "bar": {"enabled": true}},
  "hooks": {"myhook": {"enabled": true}},
  "mcp": {}
}
EOF

discover1='{"skills": [{"name": "foo"}, {"name": "bar"}], "hooks": [{"name": "myhook"}], "mcp": []}'

output1=$(run_profile_diff "$profile1" "$discover1")

added_skills1=$(printf '%s' "$output1" | jq -r '.added.skills | length')
removed_skills1=$(printf '%s' "$output1" | jq -r '.removed.skills | length')
added_hooks1=$(printf '%s' "$output1" | jq -r '.added.hooks | length')
removed_hooks1=$(printf '%s' "$output1" | jq -r '.removed.hooks | length')

if [[ "$added_skills1" == "0" ]]; then
    pass "no drift: added.skills is empty"
else
    fail "no drift: added.skills is empty" "length=$added_skills1"
fi

if [[ "$removed_skills1" == "0" ]]; then
    pass "no drift: removed.skills is empty"
else
    fail "no drift: removed.skills is empty" "length=$removed_skills1"
fi

if [[ "$added_hooks1" == "0" ]]; then
    pass "no drift: added.hooks is empty"
else
    fail "no drift: added.hooks is empty" "length=$added_hooks1"
fi

if [[ "$removed_hooks1" == "0" ]]; then
    pass "no drift: removed.hooks is empty"
else
    fail "no drift: removed.hooks is empty" "length=$removed_hooks1"
fi

# ---------------------------------------------------------------------------
# Test 2: New skill on disk not in profile
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 2: New skill on disk ==="
profile2="$TESTDIR/profile2.json"
cat > "$profile2" << 'EOF'
{
  "skills": {"foo": {"enabled": true}},
  "hooks": {},
  "mcp": {}
}
EOF

discover2='{"skills": [{"name": "foo"}, {"name": "image"}], "hooks": [], "mcp": []}'

output2=$(run_profile_diff "$profile2" "$discover2")

added_skill2=$(printf '%s' "$output2" | jq -r '.added.skills[0]')
removed_skills2=$(printf '%s' "$output2" | jq -r '.removed.skills | length')

if [[ "$added_skill2" == "image" ]]; then
    pass "new skill on disk: 'image' appears in added.skills"
else
    fail "new skill on disk: 'image' appears in added.skills" "got '$added_skill2'"
fi

if [[ "$removed_skills2" == "0" ]]; then
    pass "new skill on disk: removed.skills is empty"
else
    fail "new skill on disk: removed.skills is empty" "length=$removed_skills2"
fi

# ---------------------------------------------------------------------------
# Test 3: Removed skill — in profile, not on disk
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 3: Removed skill ==="
profile3="$TESTDIR/profile3.json"
cat > "$profile3" << 'EOF'
{
  "skills": {"foo": {"enabled": true}, "paste-image-macos": {"enabled": true}},
  "hooks": {},
  "mcp": {}
}
EOF

discover3='{"skills": [{"name": "foo"}], "hooks": [], "mcp": []}'

output3=$(run_profile_diff "$profile3" "$discover3")

removed_skill3=$(printf '%s' "$output3" | jq -r '.removed.skills[0]')
added_skills3=$(printf '%s' "$output3" | jq -r '.added.skills | length')

if [[ "$removed_skill3" == "paste-image-macos" ]]; then
    pass "removed skill: 'paste-image-macos' appears in removed.skills"
else
    fail "removed skill: 'paste-image-macos' appears in removed.skills" "got '$removed_skill3'"
fi

if [[ "$added_skills3" == "0" ]]; then
    pass "removed skill: added.skills is empty"
else
    fail "removed skill: added.skills is empty" "length=$added_skills3"
fi

# ---------------------------------------------------------------------------
# Test 4: New hook on disk not in profile
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 4: New hook on disk ==="
profile4="$TESTDIR/profile4.json"
cat > "$profile4" << 'EOF'
{"skills": {}, "hooks": {}, "mcp": {}}
EOF

discover4='{"skills": [], "hooks": [{"name": "bash-safety"}], "mcp": []}'

output4=$(run_profile_diff "$profile4" "$discover4")

added_hook4=$(printf '%s' "$output4" | jq -r '.added.hooks[0]')

if [[ "$added_hook4" == "bash-safety" ]]; then
    pass "new hook: 'bash-safety' appears in added.hooks"
else
    fail "new hook: 'bash-safety' appears in added.hooks" "got '$added_hook4'"
fi

# ---------------------------------------------------------------------------
# Test 5: Mixed drift — additions and removals in both skills and hooks
# ---------------------------------------------------------------------------
echo ""
echo "=== Test 5: Mixed drift ==="
profile5="$TESTDIR/profile5.json"
cat > "$profile5" << 'EOF'
{
  "skills": {"old-skill": {"enabled": true}},
  "hooks": {"old-hook": {"enabled": true}},
  "mcp": {}
}
EOF

discover5='{"skills": [{"name": "new-skill"}], "hooks": [{"name": "new-hook"}], "mcp": []}'

output5=$(run_profile_diff "$profile5" "$discover5")

added_skill5=$(printf '%s' "$output5" | jq -r '.added.skills[0]')
removed_skill5=$(printf '%s' "$output5" | jq -r '.removed.skills[0]')
added_hook5=$(printf '%s' "$output5" | jq -r '.added.hooks[0]')
removed_hook5=$(printf '%s' "$output5" | jq -r '.removed.hooks[0]')

if [[ "$added_skill5" == "new-skill" ]]; then
    pass "mixed drift: 'new-skill' in added.skills"
else
    fail "mixed drift: 'new-skill' in added.skills" "got '$added_skill5'"
fi

if [[ "$removed_skill5" == "old-skill" ]]; then
    pass "mixed drift: 'old-skill' in removed.skills"
else
    fail "mixed drift: 'old-skill' in removed.skills" "got '$removed_skill5'"
fi

if [[ "$added_hook5" == "new-hook" ]]; then
    pass "mixed drift: 'new-hook' in added.hooks"
else
    fail "mixed drift: 'new-hook' in added.hooks" "got '$added_hook5'"
fi

if [[ "$removed_hook5" == "old-hook" ]]; then
    pass "mixed drift: 'old-hook' in removed.hooks"
else
    fail "mixed drift: 'old-hook' in removed.hooks" "got '$removed_hook5'"
fi

echo ""
echo "=============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
