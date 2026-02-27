#!/usr/bin/env bash
# Tests for bash-safety compound command handling (shfmt-based parsing).
# Run from repo root: bash tests/test-bash-safety-compound.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/plugins/permission-manager/scripts/bash-safety.sh"

PASS=0 FAIL=0

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

echo "=== Compound commands — all segments read-only (expect allow) ==="
test_hook "ls && cat file"                  'ls && cat file'                    "allow"
test_hook "cat file | grep pattern"         'cat file | grep pattern'           "allow"
test_hook "cat file | sort | wc -l"         'cat file | sort | wc -l'           "allow"
test_hook "git log && git status"           'git log && git status'             "allow"
test_hook "git log && git status ; git diff" 'git log && git status ; git diff' "allow"
test_hook "ls ; cat file"                   'ls ; cat file'                     "allow"

echo ""
echo "=== Compound commands — mixed read/write (expect ask, most restrictive wins) ==="
test_hook "git status && rm -rf /"          'git status && rm -rf /'            "ask"
test_hook "git status && git push"          'git status && git push'            "ask"
test_hook "ls ; rm file"                    'ls ; rm file'                      "ask"
test_hook "cat file | tee output.txt"       'cat file | tee output.txt'         "ask"
test_hook "cat file && unknown_cmd"         'cat file && unknown_cmd'           "ask"

echo ""
echo "=== Compound commands — redirection in compound (expect deny) ==="
test_hook "cat file >> other"               'cat file >> other'                 "deny"
test_hook "echo test > file.txt"            'echo test > file.txt'              "deny"
test_hook "ls && echo x > f"               'ls && echo x > f'                  "deny"
test_hook "git status ; cat f > g"          'git status ; cat f > g'            "deny"

echo ""
echo "=== Quoted operators not split (expect allow) ==="
test_hook "git log --format=%H|%s"          'git log --format="%H|%s"'          "allow"

echo ""
echo "=== Destructive in compound (expect deny) ==="
test_hook "ls && find . -delete"            'ls && find . -delete'              "deny"
test_hook "cat f ; find . -exec rm {} \\;"  'cat f ; find . -exec rm {} \;'    "deny"

echo ""
echo "=== New read-only tools (expect allow) ==="
test_hook "echo hello"                      'echo hello'                        "allow"
test_hook "printf %s foo"                   'printf %s foo'                     "allow"
test_hook "command -v pandoc"               'command -v pandoc'                 "allow"
test_hook "basename /path/to/file"          'basename /path/to/file'            "allow"
test_hook "dirname /path/to/file"           'dirname /path/to/file'             "allow"
test_hook "env"                             'env'                               "allow"
test_hook "top -bn1"                        'top -bn1'                          "allow"

echo ""
echo "=== Default ask for unrecognized commands ==="
test_hook "unknown_command"                 'unknown_command'                   "ask"
test_hook "curl http://example.com"         'curl http://example.com'           "ask"
test_hook "make build"                      'make build'                        "ask"

echo ""
echo "=== fd duplication allowed (not flagged as redirection) ==="
test_hook "cmd 2>&1"                        'cmd 2>&1'                          "ask"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
