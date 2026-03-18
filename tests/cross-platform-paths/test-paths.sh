#!/usr/bin/env bash
# test-paths.sh — Test harness for cross-platform-paths.sh.
#
# Usage: bash tests/cross-platform-paths/test-paths.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UTIL_SCRIPT="$SCRIPT_DIR/../../utils/cross-platform-paths.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

# shellcheck source=../../utils/cross-platform-paths.sh
source "$UTIL_SCRIPT"

assert_eq() {
  local label="$1" expected="$2" actual="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: %s, got: %s)\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

assert_match() {
  local label="$1" pattern="$2" actual="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  if [[ "$actual" =~ $pattern ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected match: %s, got: %s)\n" "$label" "$pattern" "$actual"
    ((FAIL++)) || true
  fi
}

# ===== Function presence =====
echo "── Function presence ──"
for fn in claude_platform claude_data_dir claude_global_settings claude_project_settings \
  encode_project_path decode_project_path claude_project_dir claude_all_project_dirs; do
  assert_eq "function $fn defined" "function" "$(type -t "$fn" 2>/dev/null || echo "missing")"
done

# ===== claude_platform =====
echo "── claude_platform ──"
assert_match "returns darwin or linux" "^(darwin|linux)$" "$(claude_platform)"

# ===== claude_data_dir =====
echo "── claude_data_dir ──"
assert_eq "equals \$HOME/.claude" "${HOME}/.claude" "$(claude_data_dir)"
# No trailing slash
result="$(claude_data_dir)"
assert_eq "no trailing slash" "" "${result##*/.*[!/]}"

# ===== Settings paths =====
echo "── Settings paths ──"
assert_eq "global settings path" "${HOME}/.claude/settings.json" "$(claude_global_settings)"
assert_eq "project settings path" ".claude/settings.json" "$(claude_project_settings)"

# ===== encode_project_path =====
echo "── encode_project_path ──"
assert_eq "standard path" "-Users-foo-project" "$(encode_project_path "/Users/foo/project")"
assert_eq "dotfile path (double dash)" "-Users-foo--bar" "$(encode_project_path "/Users/foo/.bar")"
assert_eq "deep dotfile path" "-Users-stonefish--local-share-chezmoi" "$(encode_project_path "/Users/stonefish/.local/share/chezmoi")"
assert_eq "trailing slash stripped" "-Users-foo-project" "$(encode_project_path "/Users/foo/project/")"
assert_eq "empty input" "" "$(encode_project_path "")"
assert_eq "root path (trailing slash stripped to empty)" "" "$(encode_project_path "/")"
assert_eq "multiple dots" "-a--b---c" "$(encode_project_path "/a/.b/..c")"

# ===== decode_project_path =====
echo "── decode_project_path ──"
assert_eq "standard decode" "/Users/foo/project" "$(decode_project_path "-Users-foo-project")"
assert_eq "empty input" "" "$(decode_project_path "")"
# Lossy: original dots become / on decode (documented limitation)
assert_eq "lossy decode (dots become /)" "/Users/foo//bar" "$(decode_project_path "-Users-foo--bar")"

# ===== claude_project_dir =====
echo "── claude_project_dir ──"
assert_eq "project dir composition" "${HOME}/.claude/projects/-Users-foo-project" "$(claude_project_dir "/Users/foo/project")"
assert_eq "empty input returns empty" "" "$(claude_project_dir "")"

# ===== claude_all_project_dirs =====
echo "── claude_all_project_dirs ──"

# Set up temp HOME with fake project dirs
ORIG_HOME="$HOME"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"; HOME="$ORIG_HOME"' EXIT

# Test with populated directory
HOME="$TMPDIR_ROOT/home-populated"
mkdir -p "$HOME/.claude/projects/dir-a" "$HOME/.claude/projects/dir-b" "$HOME/.claude/projects/dir-c"
result="$(claude_all_project_dirs)"
count=$(echo "$result" | grep -c . || true)
assert_eq "finds 3 project dirs" "3" "$count"

# Test with empty projects directory
HOME="$TMPDIR_ROOT/home-empty"
mkdir -p "$HOME/.claude/projects"
result="$(claude_all_project_dirs)"
assert_eq "empty projects dir returns empty" "" "$result"

# Test with missing projects directory
HOME="$TMPDIR_ROOT/home-missing"
mkdir -p "$HOME"
result="$(claude_all_project_dirs)"
assert_eq "missing projects dir returns empty" "" "$result"

# Restore HOME
HOME="$ORIG_HOME"

# ===== Summary =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  \033[32m%d passed\033[0m" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  \033[31m%d failed\033[0m" "$FAIL"
fi
if [[ $SKIP -gt 0 ]]; then
  printf "  \033[33m%d skipped\033[0m" "$SKIP"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$FAIL"
