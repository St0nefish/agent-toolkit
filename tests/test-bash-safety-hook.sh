#!/usr/bin/env bash
# Tests for hooks/bash-safety/bash-safety.sh
# Run from repo root: bash tests/test-bash-safety-hook.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/plugins/bash-safety/scripts/bash-safety.sh"

PASS=0 FAIL=0

test_hook() {
  local label="$1" cmd="$2" expected="$3"
  local output json
  json=$(jq -n --arg cmd "$cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
  output=$(echo "$json" | bash "$HOOK" 2>/dev/null) || true
  local decision=""
  if echo "$output" | grep -q '"allow"'; then decision="allow"
  elif echo "$output" | grep -q '"ask"'; then decision="ask"
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

echo "=== Read-only git (expect allow) ==="
test_hook "git log"                  'git log --oneline'               "allow"
test_hook "git -C bypass"           'git -C /some/path log --oneline'  "allow"
test_hook "git diff"                'git --no-pager diff HEAD~3'       "allow"
test_hook "git branch -a"           'git branch -a'                    "allow"
test_hook "git stash list"          'git stash list'                   "allow"
test_hook "git tag -l"              'git tag -l'                       "allow"
test_hook "git config --get"        'git config --get user.name'       "allow"
test_hook "git status"              'git status'                       "allow"
test_hook "git remote -v"           'git remote -v'                    "allow"
test_hook "git worktree list"       'git worktree list'                "allow"
test_hook "git --version"           'git --version'                    "allow"
test_hook "git branch bare"         'git branch'                       "allow"
test_hook "git branch --show-current" 'git branch --show-current'      "allow"
test_hook "git tag bare"            'git tag'                          "allow"
test_hook "git remote show"         'git remote show origin'           "allow"
test_hook "git config --list"       'git config --list'                "allow"
test_hook "git stash show"          'git stash show'                   "allow"
test_hook "git blame"               'git blame file.txt'               "allow"
test_hook "git rev-parse"           'git rev-parse HEAD'               "allow"
test_hook "git ls-files"            'git ls-files'                     "allow"

echo ""
echo "=== Write git (expect ask) ==="
test_hook "git commit"              'git commit -m "test"'             "ask"
test_hook "git push"                'git push origin main'             "ask"
test_hook "git push --force"        'git push --force origin main'     "ask"
test_hook "git -C push"            'git -C /some/path push'            "ask"
test_hook "git checkout"            'git checkout feature-branch'      "ask"
test_hook "git reset --hard"        'git reset --hard HEAD~1'          "ask"
test_hook "git branch -d"           'git branch -d old-branch'         "ask"
test_hook "git stash bare"          'git stash'                        "ask"
test_hook "git stash push"          'git stash push'                   "ask"
test_hook "git stash pop"           'git stash pop'                    "ask"
test_hook "git config set"          'git config user.name test'        "ask"
test_hook "git add"                 'git add .'                        "ask"
test_hook "git merge"               'git merge feature'                "ask"
test_hook "git rebase"              'git rebase main'                  "ask"
test_hook "git tag create"          'git tag v1.0'                     "ask"
test_hook "git remote add"          'git remote add origin url'        "ask"
test_hook "git worktree add"        'git worktree add /tmp/wt branch'  "ask"
test_hook "git clean"               'git clean -fd'                    "ask"
test_hook "git branch -D"           'git branch -D old-branch'         "ask"
test_hook "git tag -d"              'git tag -d v1.0'                  "ask"
test_hook "git stash drop"          'git stash drop'                   "ask"
test_hook "git switch"              'git switch feature'               "ask"

echo ""
echo "=== Existing protections (expect ask) ==="
test_hook "redirection >"           'echo test > file.txt'             "ask"
test_hook "find -delete"            'find . -delete'                   "ask"

echo ""
echo "=== Non-git commands (expect none — no hook opinion) ==="
test_hook "ls"                      'ls -la'                           "none"
test_hook "cat"                     'cat file.txt'                     "none"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
