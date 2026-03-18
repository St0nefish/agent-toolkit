#!/usr/bin/env bash
# test-learn.sh — Test harness for learn.sh scan and suggest.
#
# Usage: bash tests/permission-manager/test-learn.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEARN_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/learn.sh"
HOOK_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/cmd-gate.sh"

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

  local all_matched=true
  local missing=""
  for pattern in "${expected_patterns[@]}"; do
    if ! echo "$TEST_OUTPUT" | grep -qi -- "$pattern"; then
      all_matched=false
      missing+="  missing: $pattern"$'\n'
    fi
  done

  if [[ "$all_matched" == true ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "%s" "$missing"
    ((FAIL++)) || true
  fi
}

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "SKIP: jq is required"
  exit 0
fi

# ===== suggest tests: basic =====
echo "── suggest: basic pattern generation ──"

# Two cargo run --bin variants → skeleton finds [cargo, run, --bin]
TEST_OUTPUT=$(printf 'cargo run --bin indexer\ncargo run --bin server\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "two cargo run --bin variants → skeleton includes --bin" "cargo" "run" "--bin"

# Single gh command → first-two-token prefix
TEST_OUTPUT=$(printf 'gh pr create --title "my pr"\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "single gh command → gh pr *" "gh pr \\*"

# Mixed tools → separate patterns
TEST_OUTPUT=$(printf 'cargo run --bin server\ngit push --force\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "mixed tools → two separate patterns" "cargo" "git"

# Varying second tokens → sub-groups by second token
TEST_OUTPUT=$(printf 'cargo run --bin server\ncargo build --release\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "varying second tokens → sub-grouped patterns" "cargo run" "cargo build"

# Empty input
TEST_OUTPUT=$(printf '' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="empty input → empty JSON array"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if [[ "$(echo "$TEST_OUTPUT" | jq -r 'length')" == "0" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s)\n" "$label" "$TEST_OUTPUT"
    ((FAIL++)) || true
  fi
fi

# ===== suggest tests: deep structure =====
echo "── suggest: skeleton-based patterns ──"

# Docker exec + cat → skeleton finds [docker, exec, cat]
TEST_OUTPUT=$(printf 'docker exec app1 cat /etc/hosts\ndocker exec app2 cat /var/log/syslog\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "docker exec cat → skeleton [docker, exec, cat]" "docker" "exec" "cat"

# Docker with --context flags → skeleton still finds exec and cat
TEST_OUTPUT=$(printf 'docker exec app1 cat /etc/hosts\ndocker --context atlas exec db1 cat /etc/my.cnf\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "docker with --context → skeleton includes exec, cat" "exec" "cat"

# Gradle --dry-run → skeleton finds --dry-run flag
TEST_OUTPUT=$(printf 'gradle build --dry-run\ngradle test --dry-run\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
run_test "gradle --dry-run → skeleton includes --dry-run" "gradle" "--dry-run"

# Verify skeleton field is present in output
TEST_OUTPUT=$(printf 'docker exec app1 cat /etc/hosts\ndocker exec app2 cat /var/log/syslog\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="skeleton field present in JSON output"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | jq -e '.[0].skeleton' >/dev/null 2>&1; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    ((FAIL++)) || true
  fi
fi

# ===== suggest tests: trailing wildcard =====
echo "── suggest: trailing wildcard logic ──"

# Commands that END with last skeleton token → no trailing ` *`
# gradle build --dry-run / gradle test --dry-run: all end with --dry-run
TEST_OUTPUT=$(printf 'gradle build --dry-run\ngradle test --dry-run\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="no trailing wildcard when commands end with last skeleton token"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  pat=$(echo "$TEST_OUTPUT" | jq -r '.[0].pattern')
  # Pattern should end with --dry-run, NOT --dry-run *
  if [[ "$pat" == *"--dry-run" ]] && [[ "$pat" != *"--dry-run *" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s)\n" "$label" "$pat"
    ((FAIL++)) || true
  fi
fi

# Commands with args AFTER last skeleton token → trailing ` *`
# docker exec app1 cat /etc/hosts / docker exec app2 cat /var/log/syslog
# skeleton: [docker, exec, cat], both have paths after cat
TEST_OUTPUT=$(printf 'docker exec app1 cat /etc/hosts\ndocker exec app2 cat /var/log/syslog\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="trailing wildcard when commands have args after last skeleton token"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  pat=$(echo "$TEST_OUTPUT" | jq -r '.[0].pattern')
  if [[ "$pat" == *"cat *" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s)\n" "$label" "$pat"
    ((FAIL++)) || true
  fi
fi

# ===== suggest tests: edge cases =====
echo "── suggest: edge cases ──"

# Single-token command (e.g. just "ls")
TEST_OUTPUT=$(printf 'ls\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="single-token command → pattern with wildcard"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  pat=$(echo "$TEST_OUTPUT" | jq -r '.[0].pattern')
  if [[ "$pat" == "ls *" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s)\n" "$label" "$pat"
    ((FAIL++)) || true
  fi
fi

# Completely disjoint commands in same first-token group → broad
# cargo run --bin server / cargo publish --registry crates
# skeleton: [cargo] → single token → sub-groups by second token
TEST_OUTPUT=$(printf 'cargo run --bin server\ncargo publish --registry crates\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="disjoint second tokens → sub-grouped into separate patterns"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  count=$(echo "$TEST_OUTPUT" | jq 'length')
  has_run=$(echo "$TEST_OUTPUT" | jq '[.[] | select(.pattern | contains("run"))] | length')
  has_publish=$(echo "$TEST_OUTPUT" | jq '[.[] | select(.pattern | contains("publish"))] | length')
  if [[ "$count" -eq 2 && "$has_run" -eq 1 && "$has_publish" -eq 1 ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s patterns)\n" "$label" "$count"
    ((FAIL++)) || true
  fi
fi

# Sub-group skeleton quality: within a subgroup, skeleton should be deeper than first two tokens
# cargo run --bin indexer / cargo run --bin server / cargo run --example foo
# Sub-group "run": skeleton should be [cargo, run] (--bin not in all 3)
TEST_OUTPUT=$(printf 'cargo run --bin indexer\ncargo run --bin server\ncargo run --example foo\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="sub-group skeleton drops non-universal tokens"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  pat=$(echo "$TEST_OUTPUT" | jq -r '.[0].pattern')
  skel_len=$(echo "$TEST_OUTPUT" | jq '.[0].skeleton | length')
  # Skeleton should be [cargo, run] — --bin is NOT in all commands
  has_bin=$(echo "$TEST_OUTPUT" | jq '.[0].skeleton | map(select(. == "--bin")) | length')
  if [[ "$skel_len" -eq 2 && "$has_bin" -eq 0 ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (skeleton len: %s, has --bin: %s)\n" "$label" "$skel_len" "$has_bin"
    ((FAIL++)) || true
  fi
fi

# Multiple identical commands → deduplicated, pattern still works
TEST_OUTPUT=$(printf 'cargo run --bin server\ncargo run --bin server\n' | bash "$LEARN_SCRIPT" suggest 2>/dev/null) || true
label="identical commands → single pattern"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  count=$(echo "$TEST_OUTPUT" | jq 'length')
  if [[ "$count" -eq 1 ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s (got: %s patterns)\n" "$label" "$count"
    ((FAIL++)) || true
  fi
fi

# ===== scan tests =====
echo "── scan: audit log reading ──"

TEMP_DIR=$(mktemp -d)
TEMP_LOG="$TEMP_DIR/audit.jsonl"

# Scan with audit log
cat >"$TEMP_LOG" <<'JSONL'
{"ts":"2026-03-18T10:00:00Z","command":"cargo run --bin indexer","decision":"ask","reason":"cargo run may modify","project":"myproject","cwd":"/home/user/myproject"}
{"ts":"2026-03-18T10:01:00Z","command":"cargo run --bin server","decision":"ask","reason":"cargo run may modify","project":"myproject","cwd":"/home/user/myproject"}
{"ts":"2026-03-18T10:02:00Z","command":"git push --force","decision":"ask","reason":"force push","project":"other","cwd":"/home/user/other"}
{"ts":"2026-03-18T10:03:00Z","command":"cargo run --bin indexer","decision":"ask","reason":"cargo run may modify","project":"myproject","cwd":"/home/user/myproject"}
JSONL

TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan 2>/dev/null) || true
run_test "scan outputs matching commands" "cargo run" "git push"

# Scan with --project filter
TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan --project myproject 2>/dev/null) || true
label="scan with --project filter"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "cargo run" && ! echo "$TEST_OUTPUT" | grep -q "git push"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: cargo run commands only, no git push"
    ((FAIL++)) || true
  fi
fi

# Scan with --since filter
cat >"$TEMP_LOG" <<'JSONL'
{"ts":"2020-01-01T10:00:00Z","command":"old command","decision":"ask","reason":"old","project":"myproject","cwd":"/home/user/myproject"}
{"ts":"2026-03-18T10:00:00Z","command":"recent command","decision":"ask","reason":"recent","project":"myproject","cwd":"/home/user/myproject"}
JSONL

TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan --since 30 2>/dev/null) || true
label="scan with --since filter"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "recent command" && ! echo "$TEST_OUTPUT" | grep -q "old command"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: recent command only, no old command"
    ((FAIL++)) || true
  fi
fi

# Scan with --decision filter
cat >"$TEMP_LOG" <<'JSONL'
{"ts":"2026-03-18T10:00:00Z","command":"git status","decision":"allow","reason":"read-only","project":"myproject","cwd":"/home/user/myproject"}
{"ts":"2026-03-18T10:01:00Z","command":"cargo run --bin server","decision":"ask","reason":"cargo run may modify","project":"myproject","cwd":"/home/user/myproject"}
{"ts":"2026-03-18T10:02:00Z","command":"find . -delete","decision":"deny","reason":"destructive","project":"myproject","cwd":"/home/user/myproject"}
JSONL

# --decision allow: only allow entries
TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan --decision allow 2>/dev/null) || true
label="scan --decision allow"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "git status" && ! echo "$TEST_OUTPUT" | grep -q "cargo run"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: git status only"
    ((FAIL++)) || true
  fi
fi

# --decision deny: only deny entries
TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan --decision deny 2>/dev/null) || true
label="scan --decision deny"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "find.*-delete" && ! echo "$TEST_OUTPUT" | grep -q "git status"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: find -delete only"
    ((FAIL++)) || true
  fi
fi

# --decision all: everything
TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan --decision all 2>/dev/null) || true
label="scan --decision all"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "git status" && echo "$TEST_OUTPUT" | grep -q "cargo run" && echo "$TEST_OUTPUT" | grep -q "find"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: all three commands"
    ((FAIL++)) || true
  fi
fi

# default (no --decision flag): ask only (backwards compatible)
TEST_OUTPUT=$(PERMISSION_AUDIT_LOG="$TEMP_LOG" bash "$LEARN_SCRIPT" scan 2>/dev/null) || true
label="scan default → ask only"
if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
  ((SKIP++)) || true
else
  if echo "$TEST_OUTPUT" | grep -q "cargo run" && ! echo "$TEST_OUTPUT" | grep -q "git status"; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    echo "  expected: cargo run only (ask), not git status (allow)"
    ((FAIL++)) || true
  fi
fi

# ===== Audit log written by cmd-gate =====
echo "── cmd-gate audit integration ──"

if ! command -v shfmt &>/dev/null; then
  echo "  SKIP: shfmt required for cmd-gate integration tests"
  ((SKIP += 5)) || true
else
  TEMP_AUDIT="$TEMP_DIR/cmd-gate-audit.jsonl"
  label="cmd-gate writes audit log for ask decision"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
  else
    # Feed an ask-classified command (cargo run) through cmd-gate
    payload=$(echo '{"tool_name":"Bash","tool_input":{"command":"cargo run"}}')
    echo "$payload" | PERMISSION_AUDIT_LOG="$TEMP_AUDIT" bash "$HOOK_SCRIPT" >/dev/null 2>&1 || true

    if [[ -f "$TEMP_AUDIT" ]] && jq -e '.command == "cargo run" and .decision == "ask"' "$TEMP_AUDIT" >/dev/null 2>&1; then
      printf "  \033[32m✓\033[0m %s\n" "$label"
      ((PASS++)) || true
    else
      printf "  \033[31m✗\033[0m %s\n" "$label"
      echo "  expected: JSONL entry with command=cargo run, decision=ask"
      ((FAIL++)) || true
    fi
  fi

  TEMP_AUDIT_ALLOW="$TEMP_DIR/cmd-gate-audit-allow.jsonl"
  label="cmd-gate writes audit log for allow decision"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
  else
    # Feed an allow-classified command (git status) through cmd-gate
    payload=$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
    echo "$payload" | PERMISSION_AUDIT_LOG="$TEMP_AUDIT_ALLOW" bash "$HOOK_SCRIPT" >/dev/null 2>&1 || true

    if [[ -f "$TEMP_AUDIT_ALLOW" ]] && jq -e '.command == "git status" and .decision == "allow"' "$TEMP_AUDIT_ALLOW" >/dev/null 2>&1; then
      printf "  \033[32m✓\033[0m %s\n" "$label"
      ((PASS++)) || true
    else
      printf "  \033[31m✗\033[0m %s\n" "$label"
      echo "  expected: JSONL entry with command=git status, decision=allow"
      ((FAIL++)) || true
    fi
  fi

  TEMP_AUDIT_DENY="$TEMP_DIR/cmd-gate-audit-deny.jsonl"
  label="cmd-gate writes audit log for deny decision (redirection)"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
  else
    # Feed a deny-classified command (output redirection) through cmd-gate
    payload=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo foo > output.txt"}}')
    echo "$payload" | PERMISSION_AUDIT_LOG="$TEMP_AUDIT_DENY" bash "$HOOK_SCRIPT" >/dev/null 2>&1 || true

    if [[ -f "$TEMP_AUDIT_DENY" ]] && jq -e '.decision == "deny"' "$TEMP_AUDIT_DENY" >/dev/null 2>&1; then
      printf "  \033[32m✓\033[0m %s\n" "$label"
      ((PASS++)) || true
    else
      printf "  \033[31m✗\033[0m %s\n" "$label"
      echo "  expected: JSONL entry with decision=deny"
      ((FAIL++)) || true
    fi
  fi

  TEMP_AUDIT_DENY2="$TEMP_DIR/cmd-gate-audit-deny2.jsonl"
  label="cmd-gate writes audit log for deny decision (find -delete)"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
  else
    # Feed a deny-classified command (find -delete) through cmd-gate
    payload=$(echo '{"tool_name":"Bash","tool_input":{"command":"find . -name *.tmp -delete"}}')
    echo "$payload" | PERMISSION_AUDIT_LOG="$TEMP_AUDIT_DENY2" bash "$HOOK_SCRIPT" >/dev/null 2>&1 || true

    if [[ -f "$TEMP_AUDIT_DENY2" ]] && jq -e '.command == "find . -name *.tmp -delete" and .decision == "deny"' "$TEMP_AUDIT_DENY2" >/dev/null 2>&1; then
      printf "  \033[32m✓\033[0m %s\n" "$label"
      ((PASS++)) || true
    else
      printf "  \033[31m✗\033[0m %s\n" "$label"
      echo "  expected: JSONL entry with command=find..., decision=deny"
      ((FAIL++)) || true
    fi
  fi
fi

rm -rf "$TEMP_DIR"

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
