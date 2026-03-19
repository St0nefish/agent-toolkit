#!/usr/bin/env bash
# test-classify.sh — Test harness for cmd-gate.sh classification.
# Feeds commands through the hook and checks expected outcomes.
#
# Usage: bash scripts/test-classify.sh [filter]
#   filter — optional grep pattern to run a subset of tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../../plugins-claude/permission-manager/scripts/cmd-gate.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

run_test() {
  local expected="$1" command="$2" label="${3:-$2}" format="${4:-claude}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local payload raw result
  if [[ "$format" == "copilot" ]]; then
    local args_json
    args_json=$(jq -n --arg c "$command" '{"command":$c}' | jq -c '.')
    payload=$(jq -n --arg t "bash" --arg a "$args_json" '{"toolName":$t,"toolArgs":$a}')
  else
    payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(jq -Rn --arg c "$command" '$c')}}")
  fi

  raw=$(echo "$payload" | bash "$HOOK_SCRIPT" 2>/dev/null)
  if [[ -z "$raw" ]]; then
    result="none"
  elif [[ "$format" == "copilot" ]]; then
    result=$(echo "$raw" | jq -r '.permissionDecision // "none"')
  else
    result=$(echo "$raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
  fi

  # Copilot CLI has no "ask" — it maps to "deny"
  local effective_expected="$expected"
  if [[ "$format" == "copilot" && "$expected" == "ask" ]]; then
    effective_expected="deny"
  fi

  if [[ "$result" == "$effective_expected" ]]; then
    printf "  \033[32m✓\033[0m %-6s %s\n" "$expected" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "$expected" "$label" "$result"
    ((FAIL++)) || true
  fi
}

run_test_both() {
  local expected="$1" command="$2" label="${3:-$2}"
  run_test "$expected" "$command" "$label" "claude"
  run_test "$expected" "$command" "$label [copilot]" "copilot"
}

# ===== ALLOW: read-only tools =====
echo "── Read-only tools ──"
run_test_both allow "cat foo.txt"
run_test_both allow "ls -la"
run_test_both allow "grep -r pattern ."
run_test_both allow "head -20 file.txt"
run_test_both allow "wc -l file.txt"
run_test_both allow "diff a.txt b.txt"
run_test_both allow "echo hello"
run_test_both allow "printf '%s\n' test"
run_test_both allow "stat file.txt"
run_test_both allow "which node"
run_test_both allow "env"
run_test_both allow "tree -L 2"

# ===== ALLOW: shell builtins =====
echo "── Shell builtins ──"
run_test_both allow "cd /tmp"
run_test_both allow "export FOO=bar"
run_test_both allow "source .env"
run_test_both allow "set -e"
run_test_both allow "type git"
run_test_both allow "bash scripts/test.sh"
run_test_both allow "sh -c 'echo hello'"

# ===== ALLOW: system tools =====
echo "── System tools ──"
run_test_both allow "pwd"
run_test_both allow "uname -a"
run_test_both allow "date"
run_test_both allow "df -h"
run_test_both allow "ps aux"
run_test_both allow "whoami"
run_test_both allow "hostname"
run_test_both allow "uptime"

# ===== ALLOW: redirections (safe) =====
echo "── Safe redirections ──"
run_test_both allow "ls 2>/dev/null" "stderr to /dev/null"
run_test_both allow "command -v node 2>/dev/null" "command -v with 2>/dev/null"
run_test_both allow "echo foo > /dev/null" "stdout to /dev/null"
run_test_both allow "cat README.md > /dev/null" "cat to /dev/null (B9)"
run_test_both allow "java -version 2>&1" "stderr to stdout (fd dup)"
run_test_both allow "cat file 2>/dev/null >> /dev/null" "stderr+stdout to /dev/null"
run_test_both allow "cat <<'EOF' > /tmp/pr-body.md
test
EOF" "heredoc to /tmp/ file"
run_test_both allow "echo foo > /tmp/test.txt" "stdout to /tmp/ file"
run_test_both allow "echo foo >> /tmp/log.txt" "append to /tmp/ file"

# ===== DENY: redirections (unsafe) =====
echo "── Unsafe redirections ──"
run_test_both deny "echo foo > output.txt" "stdout to file"
run_test_both deny "echo foo >> log.txt" "append to file"
run_test_both deny "cat input > output" "cat with stdout redirect"

# ===== ALLOW: git read-only =====
echo "── Git read-only ──"
run_test_both allow "git status"
run_test_both allow "git log --oneline -5"
run_test_both allow "git diff HEAD~1"
run_test_both allow "git show HEAD"
run_test_both allow "git blame file.txt"
run_test_both allow "git branch"
run_test_both allow "git branch -a"
run_test_both allow "git tag"
run_test_both allow "git tag -l 'v*'"
run_test_both allow "git remote -v"
run_test_both allow "git remote show origin"
run_test_both allow "git config --list"
run_test_both allow "git config --get user.name"
run_test_both allow "git worktree list"
run_test_both allow "git stash list"
run_test_both allow "git stash show"
run_test_both allow "git rev-parse HEAD"
run_test_both allow "git ls-files"
run_test_both allow "git merge-base main HEAD"

# ===== ALLOW: git branch workflow (non-protected) =====
echo "── Git branch workflow (allowed) ──"
run_test_both allow "git commit -m 'test'" "git commit (current branch)"
run_test_both allow "git push" "git push (current branch, no explicit target)"
run_test_both allow "git push origin feature-branch" "git push to feature branch"
run_test_both allow "git push -u origin wip/my-feature" "git push -u to feature branch"
run_test_both allow "git checkout -b new-branch" "git checkout -b (create branch)"
run_test_both allow "git switch -c new-feature" "git switch -c (create branch)"
run_test_both allow "git add ." "git add stages files"
run_test_both allow "git branch -d old-branch" "git branch -d non-protected"
run_test_both allow "git branch -D old-branch" "git branch -D non-protected"

# ===== DENY: git push to protected branches =====
echo "── Git push to protected branches (denied) ──"
run_test_both deny "git push origin main" "git push to main"
run_test_both deny "git push origin master" "git push to master"
run_test_both deny "git push origin HEAD:main" "git push refspec to main"
run_test_both deny "git push origin feature:master" "git push refspec to master"
run_test_both deny "git branch -d main" "git branch -d main"
run_test_both deny "git branch -D master" "git branch -D master"
run_test_both deny "git branch -m old-name main" "git branch -m to main"
run_test_both deny "git branch -D main" "git branch -D main (B1)"
run_test_both deny "git branch -m main renamed" "git branch -m main to renamed (B2)"

# ===== ALLOW: switching to protected branches (read-only) =====
echo "── Git switch to protected branch (allowed) ──"
run_test_both allow "git checkout main" "git checkout main"
run_test_both allow "git checkout master" "git checkout master"
run_test_both allow "git switch main" "git switch main"
run_test_both allow "git switch master" "git switch master"

# ===== ASK: creating branches named after protected branches =====
echo "── Git create protected branch name (ask) ──"
run_test_both ask "git checkout -b main" "git checkout -b main (create protected name)"
run_test_both ask "git checkout -B master origin/master" "git checkout -B master (reset to remote)"

# ===== ASK: git write operations (other) =====
echo "── Git write operations (ask) ──"
run_test_both ask "git merge feature"
run_test_both ask "git rebase main"
run_test_both ask "git reset HEAD~1"
run_test_both ask "git tag -a v1.0 -m 'release'"
run_test_both ask "git stash pop"
run_test_both ask "git stash drop"
run_test_both ask "git config --set user.name foo" "git config --set (write)"
run_test_both ask "git worktree add ../wt"
run_test_both ask "git push --force" "git push --force (no explicit branch)"

# ===== ALLOW: gh read-only =====
echo "── GitHub CLI read-only ──"
run_test_both allow "gh pr list"
run_test_both allow "gh pr view 123"
run_test_both allow "gh pr diff 123"
run_test_both allow "gh pr checks 123"
run_test_both allow "gh pr status"
run_test_both allow "gh issue list"
run_test_both allow "gh issue view 42"
run_test_both allow "gh issue status"
run_test_both allow "gh repo view"
run_test_both allow "gh repo view --json name,description"
run_test_both allow "gh run list"
run_test_both allow "gh run view 12345"
run_test_both allow "gh release list"
run_test_both allow "gh release view v1.0"
run_test_both allow "gh workflow list"
run_test_both allow "gh api repos/owner/repo/pulls"
run_test_both allow "gh auth status"

# ===== ASK: gh write operations =====
echo "── GitHub CLI write operations ──"
run_test_both ask "gh pr create --title test"
run_test_both ask "gh pr merge 123"
run_test_both ask "gh issue create --title test"
run_test_both ask "gh issue close 42"
run_test_both ask "gh release create v2.0"
run_test_both ask "gh repo create test-repo"

# ===== ALLOW: tea read-only =====
echo "── Gitea CLI (tea) read-only ──"
run_test_both allow "tea issues list"
run_test_both allow "tea issues"
run_test_both allow "tea issue ls"
run_test_both allow "tea i list"
run_test_both allow "tea issues 42"
run_test_both allow "tea pulls list"
run_test_both allow "tea pr list"
run_test_both allow "tea pr view 5"
run_test_both allow "tea pr view 5 --comments"
run_test_both allow "tea pr 5"
run_test_both allow "tea pr 5 --comments"
run_test_both allow "tea pr checkout 5"
run_test_both allow "tea pr co 5"
run_test_both allow "tea releases list"
run_test_both allow "tea repos list"
run_test_both allow "tea repo search myrepo"
run_test_both allow "tea branches list"
run_test_both allow "tea labels list"
run_test_both allow "tea milestones list"
run_test_both allow "tea times list"
run_test_both allow "tea notifications list"
run_test_both allow "tea org list"
run_test_both allow "tea open"
run_test_both allow "tea clone myrepo"
run_test_both allow "tea whoami"
run_test_both allow "tea api repos/owner/repo"
run_test_both allow "tea --help"
run_test_both allow "tea --version"

# ===== ASK: tea write operations =====
echo "── Gitea CLI (tea) write operations ──"
run_test_both ask "tea pr create --title test"
run_test_both ask "tea pr close 5"
run_test_both ask "tea pr review 5"
run_test_both ask "tea issues create --title test"
run_test_both ask "tea issue close 42"
run_test_both ask "tea releases create v2.0"
run_test_both ask "tea comment 'hello'"
run_test_both ask "tea login add"
run_test_both ask "tea logout"
run_test_both ask "tea webhooks create"
run_test_both ask "tea admin users"
run_test_both ask "tea labels create"
run_test_both ask "tea milestones create"
run_test_both ask "tea branches protect main"
run_test_both ask "tea actions secrets"

# ===== ALLOW: docker read-only =====
echo "── Docker read-only ──"
run_test_both allow "docker --version"
run_test_both allow "docker ps"
run_test_both allow "docker images"
run_test_both allow "docker logs container1"
run_test_both allow "docker inspect container1"
run_test_both allow "docker network ls"
run_test_both allow "docker volume ls"
run_test_both allow "docker compose ps"
run_test_both allow "docker compose logs"
run_test_both allow "docker system df"
run_test_both allow "docker --context atlas ps" "docker --context (global flag) ps"
run_test_both allow "docker --context atlas inspect container1" "docker --context inspect"
run_test_both allow "docker --context atlas logs container1" "docker --context logs"
run_test_both allow "docker -H tcp://host:2375 ps" "docker -H (global flag) ps"
run_test_both ask "docker --context atlas run ubuntu" "docker --context run (write)"

# ===== ASK: docker write operations =====
echo "── Docker write operations ──"
run_test_both ask "docker run ubuntu"
run_test_both ask "docker build ."
run_test_both ask "docker exec -it container bash"
run_test_both ask "docker rm container1"
run_test_both ask "docker compose up -d"
run_test_both ask "docker compose down"

# ===== ALLOW: npm/node read-only =====
echo "── npm/node read-only ──"
run_test_both allow "node --version"
run_test_both allow "node -v"
run_test_both allow "npm --version"
run_test_both allow "npm list"
run_test_both allow "npm ls"
run_test_both allow "npm audit"
run_test_both allow "npm outdated"
run_test_both allow "npm view react"
run_test_both allow "npm info react"

# ===== ALLOW: npm local build/test operations =====
echo "── npm local build/test ──"
run_test_both allow "npm install"
run_test_both allow "npm install react"
run_test_both allow "npm run build"
run_test_both allow "npm test"

# ===== ASK: npm publish/remote operations =====
echo "── npm publish operations ──"
run_test_both ask "npm publish"

# ===== ALLOW: pip/python read-only =====
echo "── pip/python read-only ──"
run_test_both allow "python3 --version"
run_test_both allow "pip list"
run_test_both allow "pip3 show requests"
run_test_both allow "pip freeze"
run_test_both allow "pip --version"

# ===== ALLOW: pip local install =====
echo "── pip local install ──"
run_test_both allow "pip install requests"

# ===== ASK: pip destructive operations =====
echo "── pip destructive operations ──"
run_test_both ask "pip3 uninstall flask"

# ===== ALLOW: cargo/rust read-only =====
echo "── cargo/rust read-only ──"
run_test_both allow "cargo --version"
run_test_both allow "cargo check"
run_test_both allow "cargo metadata"
run_test_both allow "cargo tree"
run_test_both allow "cargo audit"

# ===== ALLOW: cargo local build/test =====
echo "── cargo local build/test ──"
run_test_both allow "cargo build"
run_test_both allow "cargo test"
run_test_both allow "cargo clippy"
run_test_both allow "cargo fmt"
run_test_both allow "cargo doc"
run_test_both allow "cargo bench"
run_test_both allow "cargo clean"

# ===== ASK: cargo run/publish operations =====
echo "── cargo run/publish operations ──"
run_test_both ask "cargo run"
run_test_both ask "cargo install ripgrep"
run_test_both ask "cargo publish"

# ===== ALLOW: JVM read-only =====
echo "── JVM read-only ──"
run_test_both allow "java -version"
run_test_both allow "java --version"
run_test_both allow "javap MyClass"
run_test_both allow "mvn --version"
run_test_both allow "mvn dependency:tree"
run_test_both allow "mvn help:effective-pom"

# ===== ALLOW: JVM local build/test =====
echo "── JVM local build/test ──"
run_test_both allow "mvn compile"
run_test_both allow "mvn test"
run_test_both allow "mvn package"
run_test_both allow "mvn install"
run_test_both allow "mvn clean"
run_test_both allow "mvn verify"

# ===== ASK: JVM deploy/remote operations =====
echo "── JVM deploy operations ──"
run_test_both ask "mvn deploy"
run_test_both ask "mvn release:prepare"

# ===== ALLOW: gradle read-only =====
echo "── Gradle read-only ──"
run_test_both allow "gradle --version"
run_test_both allow "gradle --help"
run_test_both allow "gradle tasks"
run_test_both allow "gradle dependencies"
run_test_both allow "gradle properties"
run_test_both allow "./gradlew tasks"
run_test_both allow "gradle --dry-run build" "gradle --dry-run (read-only)"

# ===== ALLOW: gradle local build/test =====
echo "── Gradle local build/test ──"
run_test_both allow "gradle build"
run_test_both allow "gradle test"
run_test_both allow "gradle clean"
run_test_both allow "gradle assemble"
run_test_both allow "gradle check"

# ===== ASK: gradle publish/remote operations =====
echo "── Gradle publish operations ──"
run_test_both ask "./gradlew publish"
run_test_both ask "gradle uploadArchives"

# ===== ALLOW: uv read-only =====
echo "── uv read-only ──"
run_test_both allow "uv version"
run_test_both allow "uv --version"
run_test_both allow "uv -V"
run_test_both allow "uv --help"
run_test_both allow "uv tree"
run_test_both allow "uv export"
run_test_both allow "uv pip list"
run_test_both allow "uv pip show requests"
run_test_both allow "uv pip check"
run_test_both allow "uv pip freeze"
run_test_both allow "uv python list"
run_test_both allow "uv python find"
run_test_both allow "uv python dir"
run_test_both allow "uv tool list"
run_test_both allow "uv tool dir"
run_test_both allow "uv cache dir"
run_test_both allow "uv self version"
run_test_both allow "uv lock --check" "uv lock --check (read-only)"

# ===== ALLOW: uv local build/dev =====
echo "── uv local build/dev ──"
run_test_both allow "uv run pytest"
run_test_both allow "uv sync"
run_test_both allow "uv lock"
run_test_both allow "uv add requests"
run_test_both allow "uv remove flask"
run_test_both allow "uv build"
run_test_both allow "uv venv"
run_test_both allow "uv init"
run_test_both allow "uv pip install requests"
run_test_both allow "uv pip uninstall flask"
run_test_both allow "uv pip compile requirements.in"
run_test_both allow "uv pip sync requirements.txt"
run_test_both allow "uv python install 3.12"
run_test_both allow "uv python uninstall 3.11"
run_test_both allow "uv python pin 3.12"
run_test_both allow "uv tool install ruff"
run_test_both allow "uv tool uninstall ruff"
run_test_both allow "uv tool upgrade ruff"

# ===== ALLOW: uv with global flags =====
echo "── uv with global flags ──"
run_test_both allow "uv --quiet sync" "uv --quiet sync"
run_test_both allow "uv --no-cache pip list" "uv --no-cache pip list"
run_test_both allow "uv --directory /tmp/myproject tree" "uv --directory <path> tree"

# ===== ASK: uv publish/destructive =====
echo "── uv publish/destructive ──"
run_test_both ask "uv publish"
run_test_both ask "uv cache clean"
run_test_both ask "uv cache prune"
run_test_both ask "uv self update"

# ===== PASSTHROUGH: uvx =====
echo "── uvx ──"
run_test_both allow "uvx --version"
run_test_both none "uvx ruff check ." "uvx (passthrough)"
run_test_both none "uvx black ." "uvx (passthrough)"

# ===== DENY: find destructive =====
echo "── Find operations ──"
run_test_both deny "find . -name '*.tmp' -delete" "find -delete"
run_test_both deny "find . -exec rm {} \\;" "find -exec rm"
run_test_both allow "find . -name '*.txt' -exec grep -l pattern {} \\;" "find -exec grep (safe)"

# ===== ALLOW: compound commands =====
echo "── Compound commands ──"
run_test_both allow "git status && git log --oneline -3" "compound: two read-only"
run_test_both allow "pwd && uname -a" "compound: system tools"
run_test_both allow "which node && node --version" "compound: which + version"

# ===== ALLOW: compound with branch workflow =====
echo "── Compound with branch workflow ──"
run_test_both allow "git status && git push" "compound: read + push (current branch)"
run_test_both allow "git add . && git commit -m 'fix'" "compound: add + commit"

# ===== DENY: compound with protected branch =====
echo "── Compound with protected branch ──"
run_test_both deny "git status && git push origin main" "compound: read + push main"

# ===== ALLOW: compound with local build segment =====
echo "── Compound with local build segment ──"
run_test_both allow "npm list && npm install" "compound: read + local build"
run_test_both allow "cargo check && cargo build" "compound: two local build"
run_test_both allow "cd /tmp && bash test.sh" "compound: cd + bash script"

# ===== PASSTHROUGH: unrecognized commands (no opinion — defer to Claude Code) =====
echo "── Unrecognized commands (passthrough) ──"
run_test_both none "curl https://example.com" "curl (passthrough)"
run_test_both none "wget https://example.com" "wget (passthrough)"
run_test_both none "make build" "make (passthrough)"
run_test_both none "rm -rf /tmp/test" "rm (passthrough)"

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
