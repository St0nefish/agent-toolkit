#!/usr/bin/env bash
# test-classify.sh — Test harness for bash-safety.sh classification.
# Feeds commands through the hook and checks expected outcomes.
#
# Usage: bash scripts/test-classify.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/bash-safety.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

run_test() {
  local expected="$1" command="$2" label="${3:-$2}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local raw result
  raw=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(jq -Rn --arg c "$command" '$c')}}" |
    bash "$HOOK_SCRIPT" 2>/dev/null)
  if [[ -z "$raw" ]]; then
    result="none"
  else
    result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  fi

  if [[ "$result" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "$expected" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "$expected" "$label" "$result"
    ((FAIL++)) || true
  fi
}

# ===== ALLOW: read-only tools =====
echo "── Read-only tools ──"
run_test allow "cat foo.txt"
run_test allow "ls -la"
run_test allow "grep -r pattern ."
run_test allow "head -20 file.txt"
run_test allow "wc -l file.txt"
run_test allow "diff a.txt b.txt"
run_test allow "echo hello"
run_test allow "printf '%s\n' test"
run_test allow "stat file.txt"
run_test allow "which node"
run_test allow "env"
run_test allow "tree -L 2"

# ===== ALLOW: shell builtins =====
echo "── Shell builtins ──"
run_test allow "cd /tmp"
run_test allow "export FOO=bar"
run_test allow "source .env"
run_test allow "set -e"
run_test allow "type git"
run_test allow "bash scripts/test.sh"
run_test allow "sh -c 'echo hello'"

# ===== ALLOW: system tools =====
echo "── System tools ──"
run_test allow "pwd"
run_test allow "uname -a"
run_test allow "date"
run_test allow "df -h"
run_test allow "ps aux"
run_test allow "whoami"
run_test allow "hostname"
run_test allow "uptime"

# ===== ALLOW: redirections (safe) =====
echo "── Safe redirections ──"
run_test allow "ls 2>/dev/null" "stderr to /dev/null"
run_test allow "command -v node 2>/dev/null" "command -v with 2>/dev/null"
run_test allow "echo foo > /dev/null" "stdout to /dev/null"
run_test allow "java -version 2>&1" "stderr to stdout (fd dup)"
run_test allow "cat file 2>/dev/null >> /dev/null" "stderr+stdout to /dev/null"

# ===== DENY: redirections (unsafe) =====
echo "── Unsafe redirections ──"
run_test deny "echo foo > output.txt" "stdout to file"
run_test deny "echo foo >> log.txt" "append to file"
run_test deny "cat input > output" "cat with stdout redirect"

# ===== ALLOW: git read-only =====
echo "── Git read-only ──"
run_test allow "git status"
run_test allow "git log --oneline -5"
run_test allow "git diff HEAD~1"
run_test allow "git show HEAD"
run_test allow "git blame file.txt"
run_test allow "git branch"
run_test allow "git branch -a"
run_test allow "git tag"
run_test allow "git tag -l 'v*'"
run_test allow "git remote -v"
run_test allow "git remote show origin"
run_test allow "git config --list"
run_test allow "git config --get user.name"
run_test allow "git worktree list"
run_test allow "git stash list"
run_test allow "git stash show"
run_test allow "git rev-parse HEAD"
run_test allow "git ls-files"
run_test allow "git merge-base main HEAD"

# ===== ASK: git write operations =====
echo "── Git write operations ──"
run_test ask "git commit -m 'test'"
run_test ask "git push"
run_test ask "git push origin main"
run_test ask "git merge feature"
run_test ask "git rebase main"
run_test ask "git reset HEAD~1"
run_test ask "git checkout -b new-branch"
run_test ask "git branch -d old-branch"
run_test ask "git tag -a v1.0 -m 'release'"
run_test ask "git stash pop"
run_test ask "git stash drop"
run_test ask "git config --set user.name foo" "git config --set (write)"
run_test ask "git worktree add ../wt"

# ===== ALLOW: gh read-only =====
echo "── GitHub CLI read-only ──"
run_test allow "gh pr list"
run_test allow "gh pr view 123"
run_test allow "gh pr diff 123"
run_test allow "gh pr checks 123"
run_test allow "gh pr status"
run_test allow "gh issue list"
run_test allow "gh issue view 42"
run_test allow "gh issue status"
run_test allow "gh repo view"
run_test allow "gh repo view --json name,description"
run_test allow "gh run list"
run_test allow "gh run view 12345"
run_test allow "gh release list"
run_test allow "gh release view v1.0"
run_test allow "gh workflow list"
run_test allow "gh api repos/owner/repo/pulls"
run_test allow "gh auth status"

# ===== ASK: gh write operations =====
echo "── GitHub CLI write operations ──"
run_test ask "gh pr create --title test"
run_test ask "gh pr merge 123"
run_test ask "gh issue create --title test"
run_test ask "gh issue close 42"
run_test ask "gh release create v2.0"
run_test ask "gh repo create test-repo"

# ===== ALLOW: docker read-only =====
echo "── Docker read-only ──"
run_test allow "docker --version"
run_test allow "docker ps"
run_test allow "docker images"
run_test allow "docker logs container1"
run_test allow "docker inspect container1"
run_test allow "docker network ls"
run_test allow "docker volume ls"
run_test allow "docker compose ps"
run_test allow "docker compose logs"
run_test allow "docker system df"

# ===== ASK: docker write operations =====
echo "── Docker write operations ──"
run_test ask "docker run ubuntu"
run_test ask "docker build ."
run_test ask "docker exec -it container bash"
run_test ask "docker rm container1"
run_test ask "docker compose up -d"
run_test ask "docker compose down"

# ===== ALLOW: npm/node read-only =====
echo "── npm/node read-only ──"
run_test allow "node --version"
run_test allow "node -v"
run_test allow "npm --version"
run_test allow "npm list"
run_test allow "npm ls"
run_test allow "npm audit"
run_test allow "npm outdated"
run_test allow "npm view react"
run_test allow "npm info react"

# ===== ALLOW: npm local build/test operations =====
echo "── npm local build/test ──"
run_test allow "npm install"
run_test allow "npm install react"
run_test allow "npm run build"
run_test allow "npm test"

# ===== ASK: npm publish/remote operations =====
echo "── npm publish operations ──"
run_test ask "npm publish"

# ===== ALLOW: pip/python read-only =====
echo "── pip/python read-only ──"
run_test allow "python3 --version"
run_test allow "pip list"
run_test allow "pip3 show requests"
run_test allow "pip freeze"
run_test allow "pip --version"

# ===== ALLOW: pip local install =====
echo "── pip local install ──"
run_test allow "pip install requests"

# ===== ASK: pip destructive operations =====
echo "── pip destructive operations ──"
run_test ask "pip3 uninstall flask"

# ===== ALLOW: cargo/rust read-only =====
echo "── cargo/rust read-only ──"
run_test allow "cargo --version"
run_test allow "cargo check"
run_test allow "cargo metadata"
run_test allow "cargo tree"
run_test allow "cargo audit"

# ===== ALLOW: cargo local build/test =====
echo "── cargo local build/test ──"
run_test allow "cargo build"
run_test allow "cargo test"
run_test allow "cargo clippy"
run_test allow "cargo fmt"
run_test allow "cargo doc"
run_test allow "cargo bench"
run_test allow "cargo clean"

# ===== ASK: cargo run/publish operations =====
echo "── cargo run/publish operations ──"
run_test ask "cargo run"
run_test ask "cargo install ripgrep"
run_test ask "cargo publish"

# ===== ALLOW: JVM read-only =====
echo "── JVM read-only ──"
run_test allow "java -version"
run_test allow "java --version"
run_test allow "javap MyClass"
run_test allow "mvn --version"
run_test allow "mvn dependency:tree"
run_test allow "mvn help:effective-pom"

# ===== ALLOW: JVM local build/test =====
echo "── JVM local build/test ──"
run_test allow "mvn compile"
run_test allow "mvn test"
run_test allow "mvn package"
run_test allow "mvn install"
run_test allow "mvn clean"
run_test allow "mvn verify"

# ===== ASK: JVM deploy/remote operations =====
echo "── JVM deploy operations ──"
run_test ask "mvn deploy"
run_test ask "mvn release:prepare"

# ===== ALLOW: gradle read-only =====
echo "── Gradle read-only ──"
run_test allow "gradle --version"
run_test allow "gradle --help"
run_test allow "gradle tasks"
run_test allow "gradle dependencies"
run_test allow "gradle properties"
run_test allow "./gradlew tasks"
run_test allow "gradle --dry-run build" "gradle --dry-run (read-only)"

# ===== ALLOW: gradle local build/test =====
echo "── Gradle local build/test ──"
run_test allow "gradle build"
run_test allow "gradle test"
run_test allow "gradle clean"
run_test allow "gradle assemble"
run_test allow "gradle check"

# ===== ASK: gradle publish/remote operations =====
echo "── Gradle publish operations ──"
run_test ask "./gradlew publish"
run_test ask "gradle uploadArchives"

# ===== DENY: find destructive =====
echo "── Find operations ──"
run_test deny "find . -name '*.tmp' -delete" "find -delete"
run_test deny "find . -exec rm {} \\;" "find -exec rm"
run_test allow "find . -name '*.txt' -exec grep -l pattern {} \\;" "find -exec grep (safe)"

# ===== ALLOW: compound commands =====
echo "── Compound commands ──"
run_test allow "git status && git log --oneline -3" "compound: two read-only"
run_test allow "pwd && uname -a" "compound: system tools"
run_test allow "which node && node --version" "compound: which + version"

# ===== ASK: compound with write segment =====
echo "── Compound with write segment ──"
run_test ask "git status && git push" "compound: read + write"

# ===== ALLOW: compound with local build segment =====
echo "── Compound with local build segment ──"
run_test allow "npm list && npm install" "compound: read + local build"
run_test allow "cargo check && cargo build" "compound: two local build"
run_test allow "cd /tmp && bash test.sh" "compound: cd + bash script"

# ===== PASSTHROUGH: unrecognized commands (no opinion — defer to Claude Code) =====
echo "── Unrecognized commands (passthrough) ──"
run_test none "curl https://example.com" "curl (passthrough)"
run_test none "wget https://example.com" "wget (passthrough)"
run_test none "make build" "make (passthrough)"
run_test none "rm -rf /tmp/test" "rm (passthrough)"

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
