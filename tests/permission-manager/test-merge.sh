#!/usr/bin/env bash
# test-merge.sh — Test harness for merge-permissions.sh merge and remove modes.
#
# Usage: bash tests/permission-manager/test-merge.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MERGE_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/merge-permissions.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

run_test() {
  local label="$1"
  shift
  local expected_patterns=("$@")

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local all_ok=true
  for pattern in "${expected_patterns[@]}"; do
    if ! echo "$TEST_OUTPUT" | grep -qi -- "$pattern"; then
      all_ok=false
      printf "    missing: %s\n" "$pattern"
    fi
  done

  if [[ "$all_ok" == true ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    ((FAIL++)) || true
  fi
}

# Exact jq assertion: check settings.json content directly
assert_jq() {
  local label="$1" jq_expr="$2" expected="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local actual
  actual="$(jq -r "$jq_expr" "$SETTINGS")"
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "    expected: %s\n    actual:   %s\n" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq is required"
  exit 0
fi

# Set up temp directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
SETTINGS="$TEMP_DIR/settings.json"

# Helper to reset settings
reset_settings() {
  echo '{"permissions":{"allow":[],"deny":[]}}' | tee "$SETTINGS" | cat >/dev/null
}

# =========================================================================
#  MERGE MODE
# =========================================================================
echo "── Merge: basic ──"

reset_settings
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --settings "$SETTINGS" web 2>&1)
run_test "merge web → +8 allow reported" "+8 allow"
run_test "merge web → writes file" "Written to"

assert_jq "merge web → 8 entries in settings" \
  '.permissions.allow | length' "8"
assert_jq "merge web → crates.io present" \
  '[.permissions.allow[] | select(contains("crates.io"))] | length' "1"
assert_jq "merge web → WebSearch present" \
  '[.permissions.allow[] | select(. == "WebSearch")] | length' "1"
assert_jq "merge web → stackoverflow present" \
  '[.permissions.allow[] | select(contains("stackoverflow"))] | length' "1"

echo "── Merge: idempotent ──"

TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --settings "$SETTINGS" web 2>&1)
run_test "merge web again → already present" "already.*present"
assert_jq "merge web again → still 8 entries" \
  '.permissions.allow | length' "8"

echo "── Merge: dry-run ──"

reset_settings
BEFORE=$(cat "$SETTINGS")
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --dry-run --settings "$SETTINGS" web 2>&1)
run_test "merge dry-run → +8 allow reported" "+8 allow"
run_test "merge dry-run → dry run message" "dry run"
AFTER=$(cat "$SETTINGS")
if [[ "$BEFORE" == "$AFTER" ]]; then
  printf "  \033[32m✓\033[0m merge dry-run → settings unchanged\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m merge dry-run → settings were modified\n"
  ((FAIL++)) || true
fi

echo "── Merge: multi-group ──"

reset_settings
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --settings "$SETTINGS" web web-all 2>&1)
run_test "merge web+web-all → reports web" "web "
run_test "merge web+web-all → reports web-all" "web-all"
run_test "merge web+web-all → writes file" "Written to"

# web has 8 entries, web-all adds WebFetch (WebSearch already counted in web)
assert_jq "merge web+web-all → 9 entries total" \
  '.permissions.allow | length' "9"
assert_jq "merge web+web-all → blanket WebFetch present" \
  '[.permissions.allow[] | select(. == "WebFetch")] | length' "1"
assert_jq "merge web+web-all → domain entries present" \
  '[.permissions.allow[] | select(startswith("WebFetch(domain:"))] | length' "7"

echo "── Merge: preserves existing entries ──"

reset_settings
# Pre-populate with a custom entry
jq '.permissions.allow = ["Bash(npm test)"]' "$SETTINGS" | tee "$SETTINGS.tmp" | cat >/dev/null
mv "$SETTINGS.tmp" "$SETTINGS"
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web >/dev/null 2>&1
assert_jq "merge preserves pre-existing entry" \
  '[.permissions.allow[] | select(. == "Bash(npm test)")] | length' "1"
assert_jq "merge adds new entries alongside existing" \
  '.permissions.allow | length' "9"

echo "── Merge: status ──"

reset_settings
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web >/dev/null 2>&1
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --settings "$SETTINGS" --status 2>&1)
run_test "status → web shows applied" "web.*applied"
# web-all is partial (WebSearch overlaps with web group, but blanket WebFetch is missing)
run_test "status → web-all shows partial" "web-all.*partial"

echo "── Merge: list ──"

TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --list 2>&1)
run_test "list → shows web" "web "
run_test "list → shows web-all" "web-all"

# =========================================================================
#  REMOVE MODE
# =========================================================================
echo "── Remove: basic ──"

reset_settings
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web web-all >/dev/null 2>&1
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --remove --settings "$SETTINGS" web-all 2>&1)
run_test "remove web-all → reports removal count" "Total.*allow"
run_test "remove web-all → writes file" "Written to"

# web-all has WebFetch + WebSearch; both should be gone
assert_jq "remove web-all → blanket WebFetch gone" \
  '[.permissions.allow[] | select(. == "WebFetch")] | length' "0"
assert_jq "remove web-all → WebSearch gone" \
  '[.permissions.allow[] | select(. == "WebSearch")] | length' "0"
# Domain entries from web group should remain
assert_jq "remove web-all → domain entries remain" \
  '[.permissions.allow[] | select(startswith("WebFetch(domain:"))] | length' "7"

echo "── Remove: selective (only target group) ──"

reset_settings
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web web-all >/dev/null 2>&1
# Remove only web (domain entries + WebSearch), web-all's blanket WebFetch should remain
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --remove --settings "$SETTINGS" web 2>&1)
assert_jq "remove web → domain entries gone" \
  '[.permissions.allow[] | select(startswith("WebFetch(domain:"))] | length' "0"
assert_jq "remove web → blanket WebFetch remains" \
  '[.permissions.allow[] | select(. == "WebFetch")] | length' "1"

echo "── Remove: dry-run ──"

reset_settings
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web >/dev/null 2>&1
BEFORE=$(cat "$SETTINGS")
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --remove --dry-run --settings "$SETTINGS" web 2>&1)
run_test "remove dry-run → dry run message" "dry run"
run_test "remove dry-run → reports removal count" "Total.*allow"
AFTER=$(cat "$SETTINGS")
if [[ "$BEFORE" == "$AFTER" ]]; then
  printf "  \033[32m✓\033[0m remove dry-run → settings unchanged\n"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m remove dry-run → settings were modified\n"
  ((FAIL++)) || true
fi

echo "── Remove: unapplied group (no-op) ──"

reset_settings
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --remove --settings "$SETTINGS" web-all 2>&1)
run_test "remove unapplied → not applied message" "not applied"
run_test "remove unapplied → nothing to remove" "Nothing to remove"

echo "── Remove: preserves unrelated entries ──"

reset_settings
jq '.permissions.allow = ["Bash(npm test)"]' "$SETTINGS" | tee "$SETTINGS.tmp" | cat >/dev/null
mv "$SETTINGS.tmp" "$SETTINGS"
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web >/dev/null 2>&1
bash "$MERGE_SCRIPT" --remove --settings "$SETTINGS" web >/dev/null 2>&1
assert_jq "remove preserves unrelated entry" \
  '[.permissions.allow[] | select(. == "Bash(npm test)")] | length' "1"
assert_jq "remove leaves only unrelated entry" \
  '.permissions.allow | length' "1"

echo "── Remove: status after remove ──"

reset_settings
bash "$MERGE_SCRIPT" --settings "$SETTINGS" web web-all >/dev/null 2>&1
bash "$MERGE_SCRIPT" --remove --settings "$SETTINGS" web-all >/dev/null 2>&1
TEST_OUTPUT=$(bash "$MERGE_SCRIPT" --settings "$SETTINGS" --status 2>&1)
run_test "status after remove → web-all missing" "web-all.*missing"
# web is partial because WebSearch (shared with web-all) was removed
run_test "status after remove → web partial" "web.*partial"

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
