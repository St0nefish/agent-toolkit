#!/usr/bin/env bash
# test-scripts.sh — Tests for session-history-analyzer scripts
#
# Usage: bash tests/session-history-analyzer/test-scripts.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../../plugins-claude/session-history-analyzer"
DISCOVER="$PLUGIN_DIR/scripts/discover-sessions.sh"
PARSE="$PLUGIN_DIR/scripts/parse-session.sh"
STATE="$PLUGIN_DIR/scripts/state-manager.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  if [[ "$expected" == "$actual" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

assert_exit() {
  local label="$1" expected_code="$2"
  shift 2
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  local actual_code=0
  "$@" &>/dev/null || actual_code=$?
  if [[ "$actual_code" -eq "$expected_code" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected exit %d, got %d)\n" "$label" "$expected_code" "$actual_code"
    ((FAIL++)) || true
  fi
}

assert_json_field() {
  local label="$1" json="$2" field="$3" expected="$4"
  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  local actual
  actual=$(echo "$json" | jq -r "$field")
  if [[ "$expected" == "$actual" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

# ===== DISCOVER-SESSIONS.SH =====
echo "── discover-sessions.sh ──"

# Test: nonexistent projects dir -> empty output, exit 0
test_dir="$TMPDIR_BASE/discover-empty"
mkdir -p "$test_dir"
output=$(CLAUDE_PROJECTS_DIR="$test_dir/nonexistent" bash "$DISCOVER" 2>/dev/null)
assert_eq "nonexistent projects dir -> empty output" "" "$output"

# Test: empty projects dir -> empty output, exit 0
test_dir="$TMPDIR_BASE/discover-empty-dir"
mkdir -p "$test_dir/projects"
output=$(CLAUDE_PROJECTS_DIR="$test_dir/projects" bash "$DISCOVER" 2>/dev/null)
assert_eq "empty projects dir -> empty output" "" "$output"

# Test: one project with one session -> emits 1 JSON record
test_dir="$TMPDIR_BASE/discover-one"
mkdir -p "$test_dir/projects/-test-project"
echo '{"type":"user"}' >"$test_dir/projects/-test-project/abc-123.jsonl"
output=$(CLAUDE_PROJECTS_DIR="$test_dir/projects" bash "$DISCOVER" 2>/dev/null)
count=$(echo "$output" | grep -c 'session_id' || true)
assert_eq "one session -> 1 JSON record" "1" "$count"
assert_json_field "session_id field" "$output" '.session_id' "abc-123"
assert_json_field "project_slug field" "$output" '.project_slug' "-test-project"
assert_json_field "jsonl_path field contains .jsonl" "$output" '.jsonl_path | test("\\.jsonl$")' "true"
assert_json_field "mtime_epoch is number" "$output" '.mtime_epoch | type' "number"
assert_json_field "size_bytes is number" "$output" '.size_bytes | type' "number"

# Test: --project filter -> only matching project
test_dir="$TMPDIR_BASE/discover-filter"
mkdir -p "$test_dir/projects/-proj-alpha" "$test_dir/projects/-proj-beta"
echo '{"type":"user"}' >"$test_dir/projects/-proj-alpha/s1.jsonl"
echo '{"type":"user"}' >"$test_dir/projects/-proj-beta/s2.jsonl"
output=$(CLAUDE_PROJECTS_DIR="$test_dir/projects" bash "$DISCOVER" --project "alpha" 2>/dev/null)
count=$(echo "$output" | grep -c 'session_id' || true)
assert_eq "--project filter returns only matching" "1" "$count"
assert_json_field "--project filter correct slug" "$output" '.project_slug' "-proj-alpha"

# Test: subagent JSONL files excluded
test_dir="$TMPDIR_BASE/discover-subagent"
mkdir -p "$test_dir/projects/-proj-sub/subagents"
echo '{"type":"user"}' >"$test_dir/projects/-proj-sub/main.jsonl"
echo '{"type":"user"}' >"$test_dir/projects/-proj-sub/subagents/sub.jsonl"
output=$(CLAUDE_PROJECTS_DIR="$test_dir/projects" bash "$DISCOVER" 2>/dev/null)
count=$(echo "$output" | grep -c 'session_id' || true)
assert_eq "subagent files excluded" "1" "$count"
assert_json_field "only main session returned" "$output" '.session_id' "main"

# ===== PARSE-SESSION.SH =====
echo ""
echo "── parse-session.sh ──"

# Test: no args -> exit 2
assert_exit "no args -> exit 2" 2 bash "$PARSE"

# Test: nonexistent file -> exit 1
assert_exit "nonexistent file -> exit 1" 1 bash "$PARSE" "/nonexistent/file.jsonl"

# Test: minimal session
minimal="$TMPDIR_BASE/minimal.jsonl"
cat >"$minimal" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":"Hello world"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}]}}
JSONL
output=$(bash "$PARSE" "$minimal")
assert_json_field "minimal: valid JSON output" "$output" '.session_id' "minimal"
assert_json_field "minimal: started_at" "$output" '.started_at' "2026-03-18T10:00:00Z"
assert_json_field "minimal: ended_at" "$output" '.ended_at' "2026-03-18T10:00:05Z"
assert_json_field "minimal: turn_count" "$output" '.turn_count' "1"
assert_json_field "minimal: has user_prompts" "$output" '.user_prompts | length' "1"
assert_json_field "minimal: user prompt content" "$output" '.user_prompts[0]' "Hello world"

# Test: user array content with text block
array_content="$TMPDIR_BASE/array-content.jsonl"
cat >"$array_content" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"Tell me about X"}]}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Sure"}]}}
JSONL
output=$(bash "$PARSE" "$array_content")
assert_json_field "array content: text extracted" "$output" '.user_prompts[0]' "Tell me about X"

# Test: pure tool_result records excluded from user_prompts
tool_result="$TMPDIR_BASE/tool-result.jsonl"
cat >"$tool_result" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":"Start request"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","timestamp":"2026-03-18T10:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"file1.txt"}]}}
{"type":"assistant","timestamp":"2026-03-18T10:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Done"}]}}
JSONL
output=$(bash "$PARSE" "$tool_result")
assert_json_field "tool_result: excluded from prompts" "$output" '.user_prompts | length' "1"
assert_json_field "tool_result: only real prompt kept" "$output" '.user_prompts[0]' "Start request"

# Test: tool_use records counted
with_tools="$TMPDIR_BASE/with-tools.jsonl"
cat >"$with_tools" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":"Do stuff"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"pwd"}}]}}
{"type":"user","timestamp":"2026-03-18T10:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"tool_result","tool_use_id":"t2","content":"ok"}]}}
{"type":"assistant","timestamp":"2026-03-18T10:00:03.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"foo"}}]}}
JSONL
output=$(bash "$PARSE" "$with_tools")
assert_json_field "tool counts: Bash=2" "$output" '.tool_counts.Bash' "2"
assert_json_field "tool counts: Read=1" "$output" '.tool_counts.Read' "1"

# Test: hook block in tool_result counted as friction
with_hook="$TMPDIR_BASE/with-hook.jsonl"
cat >"$with_hook" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":"Run dangerous cmd"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"rm -rf /"}}]}}
{"type":"user","timestamp":"2026-03-18T10:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"Error: hook blocked this command for safety reasons"}]}}
{"type":"assistant","timestamp":"2026-03-18T10:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Sorry"}]}}
JSONL
output=$(bash "$PARSE" "$with_hook")
assert_json_field "friction: hook blocks counted" "$output" '.friction_indicators.hook_blocks' "1"

# Test: compact_boundary counted
with_compact="$TMPDIR_BASE/with-compact.jsonl"
cat >"$with_compact" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","message":{"role":"user","content":"Long session"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
{"type":"system","subtype":"compact_boundary","timestamp":"2026-03-18T11:00:00.000Z"}
{"type":"user","timestamp":"2026-03-18T11:00:01.000Z","message":{"role":"user","content":"Continue"}}
{"type":"assistant","timestamp":"2026-03-18T11:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"continuing"}]}}
JSONL
output=$(bash "$PARSE" "$with_compact")
assert_json_field "compaction counted" "$output" '.compaction_count' "1"
assert_json_field "friction compactions matches" "$output" '.friction_indicators.compactions' "1"

# Test: output has all required keys
assert_json_field "has session_id" "$output" '.session_id | type' "string"
assert_json_field "has started_at" "$output" '.started_at | type' "string"
assert_json_field "has ended_at" "$output" '.ended_at | type' "string"
assert_json_field "has turn_count" "$output" '.turn_count | type' "number"
assert_json_field "has user_prompts" "$output" '.user_prompts | type' "array"
assert_json_field "has tool_counts" "$output" '.tool_counts | type' "object"
assert_json_field "has compaction_count" "$output" '.compaction_count | type' "number"
assert_json_field "has friction_indicators" "$output" '.friction_indicators | type' "object"
assert_json_field "has workflow_signals" "$output" '.workflow_signals | type' "object"

# Test: git branch extraction
with_branch="$TMPDIR_BASE/with-branch.jsonl"
cat >"$with_branch" <<'JSONL'
{"type":"user","timestamp":"2026-03-18T10:00:00.000Z","gitBranch":"feat/cool-feature","message":{"role":"user","content":"Hi"}}
{"type":"assistant","timestamp":"2026-03-18T10:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}
JSONL
output=$(bash "$PARSE" "$with_branch")
assert_json_field "git branch extracted" "$output" '.git_branch' "feat/cool-feature"

# ===== STATE-MANAGER.SH =====
echo ""
echo "── state-manager.sh ──"

# Use isolated state dir for each test
state_dir="$TMPDIR_BASE/state-tests"

# Test: read on nonexistent file -> valid JSON {}
output=$(CLAUDE_STATE_DIR="$state_dir/empty" bash "$STATE" read)
assert_eq "read nonexistent -> {}" "{}" "$output"

# Test: mark-analyzed then is-analyzed -> exit 0
CLAUDE_STATE_DIR="$state_dir/mark" bash "$STATE" mark-analyzed "sess-001" "proj-a" "2026-03-18T10:00:00Z"
assert_exit "is-analyzed after mark -> exit 0" 0 env CLAUDE_STATE_DIR="$state_dir/mark" bash "$STATE" is-analyzed "sess-001"

# Test: is-analyzed unknown id -> exit 1
assert_exit "is-analyzed unknown -> exit 1" 1 env CLAUDE_STATE_DIR="$state_dir/mark" bash "$STATE" is-analyzed "nonexistent"

# Test: clear -> removes all entries
CLAUDE_STATE_DIR="$state_dir/clear" bash "$STATE" mark-analyzed "sess-c1" "proj-x" "2026-03-18T10:00:00Z"
CLAUDE_STATE_DIR="$state_dir/clear" bash "$STATE" clear
output=$(CLAUDE_STATE_DIR="$state_dir/clear" bash "$STATE" read)
assert_eq "clear -> empty state" "{}" "$output"

# Test: clear --project -> removes only matching
CLAUDE_STATE_DIR="$state_dir/clear-proj" bash "$STATE" mark-analyzed "s1" "proj-keep" "2026-03-18T10:00:00Z"
CLAUDE_STATE_DIR="$state_dir/clear-proj" bash "$STATE" mark-analyzed "s2" "proj-remove" "2026-03-18T10:00:00Z"
CLAUDE_STATE_DIR="$state_dir/clear-proj" bash "$STATE" clear --project "proj-remove"
assert_exit "clear --project: kept session still analyzed" 0 env CLAUDE_STATE_DIR="$state_dir/clear-proj" bash "$STATE" is-analyzed "s1"
assert_exit "clear --project: removed session not analyzed" 1 env CLAUDE_STATE_DIR="$state_dir/clear-proj" bash "$STATE" is-analyzed "s2"

# Test: summary -> valid JSON with counts
CLAUDE_STATE_DIR="$state_dir/summary" bash "$STATE" mark-analyzed "s1" "proj-a" "2026-03-18T10:00:00Z"
CLAUDE_STATE_DIR="$state_dir/summary" bash "$STATE" mark-analyzed "s2" "proj-a" "2026-03-18T11:00:00Z"
CLAUDE_STATE_DIR="$state_dir/summary" bash "$STATE" mark-analyzed "s3" "proj-b" "2026-03-18T12:00:00Z"
output=$(CLAUDE_STATE_DIR="$state_dir/summary" bash "$STATE" summary)
assert_json_field "summary: total count" "$output" '.total_analyzed' "3"
assert_json_field "summary: proj-a count" "$output" '.by_project["proj-a"]' "2"
assert_json_field "summary: proj-b count" "$output" '.by_project["proj-b"]' "1"
assert_json_field "summary: has version" "$output" '.version' "1"

# Test: no subcommand -> exit 2
assert_exit "no subcommand -> exit 2" 2 bash "$STATE"

# ===== SUMMARY =====
echo ""
TOTAL=$((PASS + FAIL + SKIP))
printf "Total: %d  PASS: %d  FAIL: %d  SKIP: %d\n" "$TOTAL" "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
