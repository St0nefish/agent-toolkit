#!/usr/bin/env bash
# Tests for hooks/bash-safety/bash-safety.sh
# Run from repo root: bash tests/test-bash-safety-hook.sh

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
  if echo "$output" | grep -q '"allow"'; then
    decision="allow"
  elif echo "$output" | grep -q '"ask"'; then
    decision="ask"
  elif echo "$output" | grep -q '"deny"'; then
    decision="deny"
  else
    decision="none"
  fi
  if [[ "$decision" == "$expected" ]]; then
    echo "PASS: $label → $decision"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label → got $decision, expected $expected"
    FAIL=$((FAIL + 1))
  fi
}

test_hook_copilot() {
  local label="$1" cmd="$2" expected="$3"
  local output json args
  args=$(jq -n --arg c "$cmd" '{"command":$c}' | jq -r '@json')
  json=$(jq -n --arg tn "bash" --arg ta "$args" '{"toolName":$tn,"toolArgs":$ta}')
  output=$(echo "$json" | bash "$HOOK" 2>/dev/null) || true
  local decision=""
  if echo "$output" | grep -q '"allow"'; then
    decision="allow"
  elif echo "$output" | grep -q '"deny"'; then
    decision="deny"
  else
    decision="none"
  fi
  if [[ "$decision" == "$expected" ]]; then
    echo "PASS [copilot]: $label → $decision"
    PASS=$((PASS + 1))
  else
    echo "FAIL [copilot]: $label → got $decision, expected $expected"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Read-only git (expect allow) ==="
test_hook "git log" 'git log --oneline' "allow"
test_hook "git -C bypass" 'git -C /some/path log --oneline' "allow"
test_hook "git diff" 'git --no-pager diff HEAD~3' "allow"
test_hook "git branch -a" 'git branch -a' "allow"
test_hook "git stash list" 'git stash list' "allow"
test_hook "git tag -l" 'git tag -l' "allow"
test_hook "git config --get" 'git config --get user.name' "allow"
test_hook "git status" 'git status' "allow"
test_hook "git remote -v" 'git remote -v' "allow"
test_hook "git worktree list" 'git worktree list' "allow"
test_hook "git --version" 'git --version' "allow"
test_hook "git branch bare" 'git branch' "allow"
test_hook "git branch --show-current" 'git branch --show-current' "allow"
test_hook "git tag bare" 'git tag' "allow"
test_hook "git remote show" 'git remote show origin' "allow"
test_hook "git config --list" 'git config --list' "allow"
test_hook "git stash show" 'git stash show' "allow"
test_hook "git blame" 'git blame file.txt' "allow"
test_hook "git rev-parse" 'git rev-parse HEAD' "allow"
test_hook "git ls-files" 'git ls-files' "allow"

echo ""
echo "=== Write git (expect ask) ==="
test_hook "git commit" 'git commit -m "test"' "ask"
test_hook "git push" 'git push origin main' "ask"
test_hook "git push --force" 'git push --force origin main' "ask"
test_hook "git -C push" 'git -C /some/path push' "ask"
test_hook "git checkout" 'git checkout feature-branch' "ask"
test_hook "git reset --hard" 'git reset --hard HEAD~1' "ask"
test_hook "git branch -d" 'git branch -d old-branch' "ask"
test_hook "git stash bare" 'git stash' "ask"
test_hook "git stash push" 'git stash push' "ask"
test_hook "git stash pop" 'git stash pop' "ask"
test_hook "git config set" 'git config user.name test' "ask"
test_hook "git add" 'git add .' "ask"
test_hook "git merge" 'git merge feature' "ask"
test_hook "git rebase" 'git rebase main' "ask"
test_hook "git tag create" 'git tag v1.0' "ask"
test_hook "git remote add" 'git remote add origin url' "ask"
test_hook "git worktree add" 'git worktree add /tmp/wt branch' "ask"
test_hook "git clean" 'git clean -fd' "ask"
test_hook "git branch -D" 'git branch -D old-branch' "ask"
test_hook "git tag -d" 'git tag -d v1.0' "ask"
test_hook "git stash drop" 'git stash drop' "ask"
test_hook "git switch" 'git switch feature' "ask"

echo ""
echo "=== Dangerous patterns (expect deny — hard block on both CLIs) ==="
test_hook "redirection >" 'echo test > file.txt' "deny"
test_hook "find -delete" 'find . -delete' "deny"
test_hook "find -exec unsafe" 'find . -exec rm -rf {} \;' "deny"
test_hook "find -execdir unsafe" 'find . -execdir chmod +x {} \;' "deny"

echo ""
echo "=== Find (expect allow — read-only file search) ==="
test_hook "find basic" 'find . -name "*.txt"' "allow"
test_hook "find type filter" 'find /tmp -type f -not -path "*/.git/*"' "allow"
test_hook "find with sort pipe" 'find . -name "*.sh" | sort' "allow"
test_hook "find -exec safe" 'find . -exec grep -l pattern {} \;' "allow"
test_hook "find -execdir safe" 'find . -execdir stat {} \;' "allow"
test_hook "find maxdepth" 'find . -maxdepth 2 -name "*.py"' "allow"

echo ""
echo "=== Read-only tools (expect allow) ==="
test_hook "cat" 'cat file.txt' "allow"
test_hook "grep" 'grep -r pattern src/' "allow"
test_hook "ls" 'ls -la' "allow"
test_hook "jq" 'jq . file.json' "allow"
test_hook "ps" 'ps aux' "allow"
test_hook "df" 'df -h' "allow"
test_hook "tar list" 'tar -tf archive.tar.gz' "allow"
test_hook "unzip list" 'unzip -l archive.zip' "allow"

echo ""
echo "=== GitHub CLI (expect allow/ask) ==="
test_hook "gh pr list" 'gh pr list' "allow"
test_hook "gh issue view" 'gh issue view 123' "allow"
test_hook "gh repo view" 'gh repo view' "allow"
test_hook "gh run list" 'gh run list' "allow"
test_hook "gh workflow list" 'gh workflow list' "allow"
test_hook "gh auth status" 'gh auth status' "allow"
test_hook "gh pr merge" 'gh pr merge 42' "ask"
test_hook "gh issue create" 'gh issue create' "ask"
test_hook "gh release create" 'gh release create v1.0' "ask"

echo ""
echo "=== Docker (expect allow/ask) ==="
test_hook "docker ps" 'docker ps' "allow"
test_hook "docker images" 'docker images' "allow"
test_hook "docker logs" 'docker logs mycontainer' "allow"
test_hook "docker inspect" 'docker inspect mycontainer' "allow"
test_hook "docker compose ps" 'docker compose ps' "allow"
test_hook "docker compose logs" 'docker compose logs' "allow"
test_hook "docker run" 'docker run -it ubuntu bash' "ask"
test_hook "docker build" 'docker build -t myimage .' "ask"
test_hook "docker exec" 'docker exec container cmd' "ask"
test_hook "docker rm" 'docker rm container' "ask"

echo ""
echo "=== npm / Node.js (expect allow/ask) ==="
test_hook "npm list" 'npm list' "allow"
test_hook "npm audit" 'npm audit' "allow"
test_hook "npm outdated" 'npm outdated' "allow"
test_hook "node --version" 'node --version' "allow"
test_hook "yarn list" 'yarn list' "allow"
test_hook "pnpm list" 'pnpm list' "allow"
test_hook "npm install" 'npm install express' "ask"
test_hook "npm run" 'npm run build' "ask"
test_hook "npm ci" 'npm ci' "ask"

echo ""
echo "=== pip / Python (expect allow/ask) ==="
test_hook "pip list" 'pip list' "allow"
test_hook "pip freeze" 'pip freeze' "allow"
test_hook "pip3 show" 'pip3 show requests' "allow"
test_hook "python --version" 'python3 --version' "allow"
test_hook "uv --version" 'uv --version' "allow"
test_hook "uv pip list" 'uv pip list' "allow"
test_hook "poetry show" 'poetry show' "allow"
test_hook "pip install" 'pip install requests' "ask"
test_hook "pip3 uninstall" 'pip3 uninstall requests' "ask"
test_hook "poetry install" 'poetry install' "ask"

echo ""
echo "=== cargo / Rust (expect allow/ask) ==="
test_hook "cargo --version" 'cargo --version' "allow"
test_hook "cargo check" 'cargo check' "allow"
test_hook "cargo audit" 'cargo audit' "allow"
test_hook "cargo metadata" 'cargo metadata' "allow"
test_hook "cargo tree" 'cargo tree' "allow"
test_hook "rustc --version" 'rustc --version' "allow"
test_hook "rustup show" 'rustup show' "allow"
test_hook "cargo build" 'cargo build' "ask"
test_hook "cargo test" 'cargo test' "ask"
test_hook "cargo run" 'cargo run' "ask"

echo ""
echo "=== JVM tools (expect allow/ask) ==="
test_hook "java --version" 'java --version' "allow"
test_hook "java -version" 'java -version' "allow"
test_hook "javac --version" 'javac --version' "allow"
test_hook "javap" 'javap MyClass.class' "allow"
test_hook "kotlin -version" 'kotlin -version' "allow"
test_hook "mvn --version" 'mvn --version' "allow"
test_hook "mvn dependency:tree" 'mvn dependency:tree' "allow"
test_hook "mvn help:effective-pom" 'mvn help:effective-pom' "allow"
test_hook "mvn install" 'mvn install' "ask"
test_hook "mvn clean" 'mvn clean' "ask"

echo ""
echo "=== Copilot CLI format — read-only (expect allow) ==="
test_hook_copilot "copilot git log" 'git log --oneline' "allow"
test_hook_copilot "copilot cat" 'cat file.txt' "allow"
test_hook_copilot "copilot grep" 'grep -r foo src/' "allow"
test_hook_copilot "copilot gh pr list" 'gh pr list' "allow"
test_hook_copilot "copilot docker ps" 'docker ps' "allow"
test_hook_copilot "copilot npm list" 'npm list' "allow"
test_hook_copilot "copilot pip list" 'pip list' "allow"
test_hook_copilot "copilot cargo check" 'cargo check' "allow"

echo ""
echo "=== Copilot CLI format — write ops (expect deny — no ask in Copilot) ==="
test_hook_copilot "copilot git commit" 'git commit -m "test"' "deny"
test_hook_copilot "copilot git push" 'git push origin main' "deny"
test_hook_copilot "copilot gradle build" './gradlew build' "deny"
test_hook_copilot "copilot gh pr merge" 'gh pr merge 42' "deny"
test_hook_copilot "copilot docker run" 'docker run -it ubuntu bash' "deny"
test_hook_copilot "copilot npm install" 'npm install express' "deny"
test_hook_copilot "copilot pip install" 'pip install requests' "deny"
test_hook_copilot "copilot cargo build" 'cargo build' "deny"
test_hook_copilot "copilot mvn install" 'mvn install' "deny"

echo ""
echo "=== Copilot CLI format — dangerous patterns (expect deny) ==="
test_hook_copilot "copilot redirection" 'echo test > file.txt' "deny"
test_hook_copilot "copilot find -delete" 'find . -delete' "deny"
test_hook_copilot "copilot find basic" 'find . -name "*.txt"' "allow"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
