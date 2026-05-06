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

  # "ask" is now passthrough on all formats — hook exits 0 with no output and lets
  # the CLI's own permission mode decide (auto mode runs it, interactive mode prompts)
  local effective_expected="$expected"
  if [[ "$expected" == "ask" ]]; then
    effective_expected="none"
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
run_test_both allow "git worktree add ../wt" "git worktree add (safe management)"
run_test_both allow "git worktree remove ../wt" "git worktree remove (safe management)"
run_test_both allow "git worktree prune" "git worktree prune (safe management)"
run_test_both allow "git stash list"
run_test_both allow "git stash show"
run_test_both allow "git rev-parse HEAD"
run_test_both allow "git ls-files"
run_test_both allow "git merge-base main HEAD"
run_test_both allow "git fetch" "git fetch (read-only)"
run_test_both allow "git fetch origin" "git fetch origin (read-only)"
run_test_both allow "git fetch --all" "git fetch --all (read-only)"
run_test_both allow "git bisect log" "git bisect (read-only)"
run_test_both allow "git archive HEAD" "git archive (read-only)"

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
run_test_both ask "git push --force" "git push --force (no explicit branch)"
run_test_both ask "git pull" "git pull (modifies working tree)"
run_test_both ask "git cherry-pick abc123" "git cherry-pick (modifies state)"
run_test_both ask "git restore file.txt" "git restore (modifies working tree)"
run_test_both ask "git rm file.txt" "git rm (removes tracked file)"
run_test_both deny "git reset --hard HEAD~1" "git reset --hard (destructive)"
run_test_both deny "git clean -fd" "git clean (removes untracked files)"

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
run_test_both ask "docker rm container1"
run_test_both ask "docker compose up -d"
run_test_both ask "docker compose down"

# ===== docker exec inner command classification =====
echo "── Docker exec inner command ──"
run_test_both allow "docker exec container1 cat /etc/hosts" "docker exec cat (read-only inner)"
run_test_both allow "docker exec -it container1 grep pattern /var/log/app.log" "docker exec grep (read-only inner)"
run_test_both allow "docker exec --user root container1 ls /tmp" "docker exec --user flag + read-only inner"
run_test_both allow "docker exec -w /app container1 head -5 README.md" "docker exec -w flag + read-only inner"
run_test_both allow "docker exec -e FOO=bar container1 cat /proc/cpuinfo" "docker exec -e flag + read-only inner"
run_test_both allow "docker --context atlas exec container1 cat /etc/hosts" "docker --context exec (global flag + inner)"
run_test_both ask "docker exec container1 cargo publish" "docker exec cargo publish (ask inner)"
run_test_both ask "docker exec -it container1 bash" "docker exec bash (unrecognized inner → ask)"
run_test_both deny "docker exec container1 find /tmp -delete" "docker exec find -delete (deny inner)"

# ===== ALLOW: curl read-only =====
echo "── curl read-only ──"
run_test_both allow "curl https://example.com"
run_test_both allow "curl -sL https://example.com"
run_test_both allow "curl -sS https://example.com"
run_test_both allow "curl -sI https://example.com" "curl -sI (HEAD)"
run_test_both allow "curl -I https://example.com" "curl -I (HEAD)"
run_test_both allow "curl -L --compressed https://example.com"
run_test_both allow "curl -H 'Authorization: Bearer x' https://example.com" "curl -H header"
run_test_both allow "curl -A 'agent' https://example.com" "curl -A user agent"
run_test_both allow "curl -u user:pass https://example.com" "curl -u basic auth"
run_test_both allow "curl --max-time 5 https://example.com" "curl --max-time"
run_test_both allow "curl -X GET https://example.com" "curl -X GET"
run_test_both allow "curl -X HEAD https://example.com" "curl -X HEAD"
run_test_both allow "curl -XGET https://example.com" "curl -XGET (attached)"
run_test_both allow "curl -o /tmp/foo.json https://example.com" "curl -o /tmp/ (scratch)"
run_test_both allow "curl -o /dev/null -w '%{http_code}' https://example.com" "curl -o /dev/null"
run_test_both allow "curl --output=/tmp/foo https://example.com" "curl --output=/tmp/"
run_test_both allow "curl -sL 'https://hub.docker.com/v2/repositories/seerr/seerr/tags?page_size=100'" "curl docker hub api"

# ===== ASK: curl write/mutating operations =====
echo "── curl write/mutating ──"
run_test_both ask "curl -X POST https://example.com" "curl -X POST"
run_test_both ask "curl -X PUT https://example.com" "curl -X PUT"
run_test_both ask "curl -X DELETE https://example.com" "curl -X DELETE"
run_test_both ask "curl -XPOST https://example.com" "curl -XPOST (attached)"
run_test_both ask "curl -d '{\"x\":1}' https://example.com" "curl -d data"
run_test_both ask "curl --data-binary @file https://example.com" "curl --data-binary"
run_test_both ask "curl -F field=value https://example.com" "curl -F form"
run_test_both ask "curl -T file https://example.com" "curl -T upload"
run_test_both ask "curl --upload-file file https://example.com" "curl --upload-file"
run_test_both ask "curl -O https://example.com/file.zip" "curl -O remote-name"
run_test_both ask "curl -o /etc/hosts https://example.com" "curl -o non-scratch path"
run_test_both ask "curl -o ./out.txt https://example.com" "curl -o cwd-relative"
run_test_both ask "curl --output=./out.txt https://example.com" "curl --output= non-scratch"
run_test_both ask "curl -K config.txt https://example.com" "curl -K config"
run_test_both ask "curl --cookie-jar jar.txt https://example.com" "curl --cookie-jar"
run_test_both ask "curl -sLo out.txt https://example.com" "curl -sLo bundle (writes file)"
run_test_both ask "curl -sLd '{}' https://example.com" "curl -sLd bundle (data)"

# ===== ALLOW: curl pipelines (regression for the python3 case) =====
echo "── curl pipelines ──"
run_test_both allow "curl -sL https://example.com | jq ." "curl | jq"
run_test_both allow "curl -sL https://example.com | grep foo | head -5" "curl | grep | head"
run_test_both allow "curl -sL https://example.com 2>&1 | jq -r '.results[].name' | head -30" "curl with stderr redirect | jq | head"

# ===== curl + web-permissions domain integration =====
# When web-permissions is in "domains" mode, curl URLs must match the allow-list.
# In "off" / "all" mode, curl auto-allows any read fetch (current behavior).
echo "── curl + web-permissions domains ──"

CURL_WEB_TMP=$(mktemp -d)
trap 'rm -rf "$CURL_WEB_TMP"' EXIT
CURL_WEB_PROJECT="$CURL_WEB_TMP/web-permissions.json"
export WEB_PERMISSIONS_GLOBAL="$CURL_WEB_TMP/global-empty.json"
export WEB_PERMISSIONS_PROJECT="$CURL_WEB_PROJECT"

# domains mode: only allow-listed hosts pass
echo '{"mode":"domains","domains":["github.com","hub.docker.com","docker.io"]}' >"$CURL_WEB_PROJECT"
run_test_both allow "curl -sL https://hub.docker.com/v2/repositories/seerr/seerr/tags" "domains: hub.docker.com (exact match)"
run_test_both allow "curl -sL https://api.github.com/repos/anthropics/claude-code" "domains: api.github.com (subdomain match)"
run_test_both allow "curl -sL https://hub.docker.com/v2/foo | jq -r '.name'" "domains: pipeline through allow-listed host"
run_test_both ask "curl -sL https://evil.example.com/secrets" "domains: unlisted host → ask"
run_test_both ask "curl -sL https://example.com" "domains: bare unlisted host → ask"
# When ANY URL in the command is unlisted, ask
run_test_both ask "curl https://hub.docker.com/foo https://evil.com/bar" "domains: one good + one bad → ask"
# No URL token at all (e.g. --version) — allow
run_test_both allow "curl --version" "domains: no URL → allow"
run_test_both allow "curl --help" "domains: --help no URL → allow"
# Headers with non-URL values are correctly skipped
run_test_both allow "curl -H 'Authorization: Bearer abc' https://hub.docker.com/foo" "domains: -H non-URL value skipped"
run_test_both allow "curl -A 'my-agent/1.0' https://hub.docker.com/foo" "domains: -A user agent skipped"
# Single-token URL-shaped flag values get consumed correctly
run_test_both allow "curl --referer https://elsewhere.com https://hub.docker.com/foo" "domains: --referer single-token value consumed"
run_test_both allow "curl -e https://elsewhere.com https://hub.docker.com/foo" "domains: -e referer single-token value consumed"
# Known limitation: a multi-word header value containing a URL (e.g. -H 'Referer: https://x.com')
# gets re-split by the classifier's whitespace tokenizer and the URL inside is treated as a
# separate fetch URL. Asking is the safe answer — a Referer leak isn't a fetch but the user
# can still approve. Most curl usage doesn't put URLs in header values.
run_test_both ask "curl -H 'Referer: https://elsewhere.com' https://hub.docker.com/foo" "domains: -H 'Referer: URL' multi-word value (false positive → ask)"

# all mode: any URL passes (read-only flags only)
echo '{"mode":"all"}' >"$CURL_WEB_PROJECT"
run_test_both allow "curl -sL https://random.example.org/data" "all: any URL allowed"

# off mode: no domain check, current blanket-allow behavior
echo '{"mode":"off"}' >"$CURL_WEB_PROJECT"
run_test_both allow "curl -sL https://random.example.org/data" "off: any URL allowed"

# Missing config file → behaves like off
rm -f "$CURL_WEB_PROJECT"
run_test_both allow "curl -sL https://random.example.org/data" "no config → any URL allowed"

unset WEB_PERMISSIONS_GLOBAL WEB_PERMISSIONS_PROJECT
rm -rf "$CURL_WEB_TMP"
trap - EXIT

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

# ===== ALLOW: python -c read-only (AST-checked) =====
echo "── python -c read-only ──"
run_test_both allow "python3 -c 'import json; print(json.dumps({}))'" \
  "python -c json single-quoted"
run_test_both allow 'python3 -c "import json; print(1)"' \
  "python -c json double-quoted"
run_test_both allow "python3 -c 'import csv,sys; r=csv.reader(open(\"/tmp/x\")); [print(row) for row in r]'" \
  "python -c csv read"
run_test_both allow "python3 -c 'import re; print(re.findall(r\"\\d+\", \"a1\"))'" \
  "python -c regex"
run_test_both allow "python3 -c 'from datetime import datetime; print(datetime.now())'" \
  "python -c datetime"
run_test_both allow "python3 -c 'from os.path import join; print(join(\"a\",\"b\"))'" \
  "python -c os.path import"
run_test_both allow "python3 -c 'open(\"/tmp/x\", \"r\").read()'" \
  "python -c open read mode"
run_test_both allow "python3 -c 'open(\"/tmp/x\")'" \
  "python -c open default mode"
run_test_both allow "python3 -u -c 'import json; print(1)'" \
  "python -c with -u flag"
run_test_both allow "python3 -m base64 -d /tmp/x" \
  "python -m base64"

# ===== ASK: python -c with unsafe operations =====
echo "── python -c unsafe ──"
run_test_both ask "python3 -c 'import subprocess; subprocess.run([\"ls\"])'" \
  "python -c subprocess"
run_test_both ask "python3 -c 'import os; os.system(\"ls\")'" \
  "python -c os.system"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"w\").write(\"hi\")'" \
  "python -c open write mode"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"a\")'" \
  "python -c open append mode"
run_test_both ask "python3 -c 'open(\"/tmp/x\", mode=\"wb\")'" \
  "python -c open mode=wb keyword"
run_test_both ask "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://x\")'" \
  "python -c urllib"
run_test_both ask "python3 -c 'import shutil; shutil.rmtree(\"/tmp/x\")'" \
  "python -c shutil"
run_test_both ask "python3 -c 'exec(\"print(1)\")'" \
  "python -c exec"
run_test_both ask "python3 -c 'eval(\"1+1\")'" \
  "python -c eval"
run_test_both ask "python3 -c '__import__(\"os\").system(\"ls\")'" \
  "python -c __import__"
run_test_both ask "python3 -c '().__class__.__bases__[0].__subclasses__()'" \
  "python -c dunder escape"
run_test_both ask "python3 -c 'getattr(__builtins__, \"eval\")(\"1\")'" \
  "python -c getattr"
run_test_both ask "python3 -c 'import pickle; pickle.loads(b\"\")'" \
  "python -c pickle"
run_test_both ask "python3 -c 'from pathlib import Path; Path(\"/tmp/x\").write_text(\"y\")'" \
  "python -c pathlib"

# ===== ALLOW: complex JSON parsing =====
# This is the dominant real-world use case for python -c — Claude reaches for
# Python to parse/aggregate/filter JSON files with shapes that are awkward in
# jq. All of these must auto-allow without prompting.
echo "── python -c complex JSON parsing ──"

_PY_JSONL_COUNTER=$(
  cat <<'PY'
import json
counts = {}
with open("/tmp/log.jsonl") as f:
    for line in f:
        try:
            obj = json.loads(line)
            counts[obj.get("event_type", "unknown")] = counts.get(obj.get("event_type", "unknown"), 0) + 1
        except json.JSONDecodeError:
            continue
for k, v in sorted(counts.items(), key=lambda x: -x[1]):
    print(f"{k}: {v}")
PY
)
run_test_both allow "python3 -c '$_PY_JSONL_COUNTER'" "complex: jsonl event counter"

_PY_NESTED_TRAVERSAL=$(
  cat <<'PY'
import json
data = json.load(open("/tmp/api.json"))
for user in data.get("users", []):
    name = user.get("name", "?")
    for project in user.get("projects", []):
        pname = project.get("name", "?")
        for task in project.get("tasks", []):
            if task.get("status") == "open":
                ttitle = task.get("title", "?")
                print(f"{name} -> {pname} -> {ttitle}")
PY
)
run_test_both allow "python3 -c '$_PY_NESTED_TRAVERSAL'" "complex: nested user/project/task traversal"

_PY_SCHEMA_CHECK=$(
  cat <<'PY'
import json
errors = []
with open("/tmp/config.json") as f:
    cfg = json.load(f)
for k in ["name", "version", "main"]:
    if k not in cfg:
        errors.append(f"missing key: {k}")
if "dependencies" in cfg and not isinstance(cfg["dependencies"], dict):
    errors.append("dependencies must be a dict")
print("\n".join(errors) or "OK")
PY
)
run_test_both allow "python3 -c '$_PY_SCHEMA_CHECK'" "complex: json schema check"

_PY_MULTI_FILE_STATS=$(
  cat <<'PY'
import json
from collections import Counter
import statistics
durations = []
tags = Counter()
for path in ["/tmp/run1.json", "/tmp/run2.json", "/tmp/run3.json"]:
    with open(path) as f:
        data = json.load(f)
    durations.append(data.get("duration_ms", 0))
    tags.update(data.get("tags", []))
print(f"mean: {statistics.mean(durations):.2f}ms")
print(f"median: {statistics.median(durations):.2f}ms")
print(f"top tags: {tags.most_common(5)}")
PY
)
run_test_both allow "python3 -c '$_PY_MULTI_FILE_STATS'" "complex: multi-file aggregated stats"

_PY_REGEX_FILTER=$(
  cat <<'PY'
import json, re
pattern = re.compile(r"error.*timeout", re.IGNORECASE)
matches = []
with open("/tmp/events.jsonl") as f:
    for line in f:
        obj = json.loads(line)
        msg = obj.get("message", "")
        if pattern.search(msg):
            matches.append((obj.get("timestamp"), msg[:100]))
matches.sort()
for ts, msg in matches[:20]:
    print(f"{ts}: {msg}")
PY
)
run_test_both allow "python3 -c '$_PY_REGEX_FILTER'" "complex: jsonl regex value filter"

_PY_DATETIME_FILTER=$(
  cat <<'PY'
import json
from datetime import datetime, timedelta, timezone
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
recent = []
with open("/tmp/events.jsonl") as f:
    for line in f:
        obj = json.loads(line)
        ts = datetime.fromisoformat(obj.get("timestamp", "").replace("Z", "+00:00"))
        if ts >= cutoff:
            recent.append(obj)
print(f"recent: {len(recent)}")
PY
)
run_test_both allow "python3 -c '$_PY_DATETIME_FILTER'" "complex: datetime-window filter"

_PY_PRETTY_FILTER=$(
  cat <<'PY'
import json
with open("/tmp/api.json") as f:
    data = json.load(f)
filtered = {k: v for k, v in data.items() if k in ("id", "name", "status", "created_at")}
print(json.dumps(filtered, indent=2, sort_keys=True))
PY
)
run_test_both allow "python3 -c '$_PY_PRETTY_FILTER'" "complex: pretty-print + dict comprehension"

_PY_RECURSIVE_WALK=$(
  cat <<'PY'
import json
def walk(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for i, item in enumerate(node):
            yield from walk(item, f"{path}[{i}]")
    else:
        yield (path, node)
with open("/tmp/deep.json") as f:
    data = json.load(f)
for path, value in walk(data):
    if isinstance(value, str) and len(value) > 100:
        print(f"{path}: {value[:80]}...")
PY
)
run_test_both allow "python3 -c '$_PY_RECURSIVE_WALK'" "complex: recursive json walker (function def + yield from)"

_PY_JSON_DIFF=$(
  cat <<'PY'
import json
with open("/tmp/before.json") as f:
    before = json.load(f)
with open("/tmp/after.json") as f:
    after = json.load(f)
for k in sorted(set(before) | set(after)):
    if k not in before:
        print(f"+ {k}: {after[k]}")
    elif k not in after:
        print(f"- {k}: {before[k]}")
    elif before[k] != after[k]:
        print(f"~ {k}: {before[k]!r} -> {after[k]!r}")
PY
)
run_test_both allow "python3 -c '$_PY_JSON_DIFF'" "complex: json diff with set ops"

_PY_RPC_GROUPING=$(
  cat <<'PY'
import json
from collections import defaultdict
methods = defaultdict(list)
with open("/tmp/rpc.jsonl") as f:
    for line in f:
        msg = json.loads(line)
        if msg.get("method"):
            methods[msg["method"]].append(msg.get("duration_ms", 0))
for m, durs in sorted(methods.items()):
    avg = sum(durs) / len(durs) if durs else 0
    print(f"{m:30s} count={len(durs):4d} avg={avg:7.2f}ms")
PY
)
run_test_both allow "python3 -c '$_PY_RPC_GROUPING'" "complex: defaultdict per-method stats"

_PY_USER_EXAMPLE=$(
  cat <<'PY'
import json
messages = []
with open("/tmp/foo.jsonl") as f:
    for line in f:
        try:
            obj = json.loads(line)
            if obj.get("type") in ("user", "assistant"):
                role = obj.get("type")
                msg = obj.get("message", {})
                content = msg.get("content", "")
                if isinstance(content, list):
                    texts = []
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            texts.append(c.get("text", ""))
                        elif isinstance(c, dict) and c.get("type") == "tool_use":
                            name = c.get("name", "")
                            texts.append(f"[TOOL:{name}]")
                    content = " ".join(texts)
                ts = obj.get("timestamp", "")
                messages.append((ts, role, str(content)))
        except: pass
print(f"Total: {len(messages)} messages")
mid = len(messages) // 2
for ts, role, content in messages[mid-5:mid+25]:
    print(f"[{ts}] {role}: {content[:400]}")
    print()
PY
)
run_test_both allow "python3 -c '$_PY_USER_EXAMPLE'" "complex: real session-jsonl extractor (the canonical case)"

_PY_BASE64_HASH=$(
  cat <<'PY'
import json, base64, hashlib
with open("/tmp/payloads.jsonl") as f:
    for line in f:
        obj = json.loads(line)
        raw = base64.b64decode(obj.get("blob", ""))
        digest = hashlib.sha256(raw).hexdigest()[:16]
        idstr = str(obj.get("id"))
        print(f"{idstr:>10} {len(raw):>8}B  sha256={digest}")
PY
)
run_test_both allow "python3 -c '$_PY_BASE64_HASH'" "complex: base64-decode + sha256 each row"

_PY_UNIQUE_BY_DAY=$(
  cat <<'PY'
import json
from collections import defaultdict
from datetime import datetime
by_day = defaultdict(set)
with open("/tmp/events.jsonl") as f:
    for line in f:
        obj = json.loads(line)
        if not obj.get("user_id"):
            continue
        ts = obj.get("ts", "")
        try:
            day = datetime.fromisoformat(ts).date().isoformat()
        except (ValueError, TypeError):
            continue
        by_day[day].add(obj["user_id"])
for day in sorted(by_day):
    print(f"{day}: {len(by_day[day])} users")
PY
)
run_test_both allow "python3 -c '$_PY_UNIQUE_BY_DAY'" "complex: unique users per day"

_PY_PERCENTILES=$(
  cat <<'PY'
import json
import statistics
durations = []
with open("/tmp/spans.jsonl") as f:
    for line in f:
        obj = json.loads(line)
        if "duration_ms" in obj:
            durations.append(obj["duration_ms"])
durations.sort()
quantiles = statistics.quantiles(durations, n=100)
print(f"count: {len(durations)}")
print(f"p50:   {quantiles[49]:.1f}ms")
print(f"p95:   {quantiles[94]:.1f}ms")
print(f"p99:   {quantiles[98]:.1f}ms")
print(f"max:   {max(durations):.1f}ms")
PY
)
run_test_both allow "python3 -c '$_PY_PERCENTILES'" "complex: latency percentile summary"

_PY_GET_PATH=$(
  cat <<'PY'
import json
def get_path(obj, *keys, default=None):
    for k in keys:
        if not isinstance(obj, dict) or k not in obj:
            return default
        obj = obj[k]
    return obj
with open("/tmp/api.json") as f:
    data = json.load(f)
for item in data.get("items", []):
    name = get_path(item, "metadata", "name", default="?")
    status = get_path(item, "status", "phase", default="Unknown")
    containers = get_path(item, "spec", "containers", default=[{}])
    image = containers[0].get("image", "?") if containers else "?"
    print(f"{name:30s} {status:12s} {image}")
PY
)
run_test_both allow "python3 -c '$_PY_GET_PATH'" "complex: nested key extraction with helper fn"

# ===== ASK: python -c adversarial / sandbox-escape attempts =====
# Each of these is a real attempted bypass — process exec, file write, network
# egress, or scope-leak via constructs that look benign. They MUST classify as
# ask, never allow. If any of these flips to allow, the static check is broken.
echo "── python -c adversarial / sandbox-escape attempts ──"

# --- sys.modules pivot (transitive os via allowed import) ---
run_test_both ask "python3 -c 'import sys, json; sys.modules[\"os\"].system(\"id\")'" \
  "escape: sys.modules subscript"
run_test_both ask "python3 -c 'import sys, json; sys.modules.get(\"os\").system(\"id\")'" \
  "escape: sys.modules.get"
run_test_both ask "python3 -c 'from sys import modules
import json
modules[\"os\"].system(\"id\")'" \
  "escape: from sys import modules (rebind to clean Name)"
run_test_both ask "python3 -c 'from sys import modules as m
import json
m[\"os\"].system(\"id\")'" \
  "escape: from sys import modules as m (alias)"
run_test_both ask "python3 -c 'from sys import *'" \
  "escape: wildcard import from sys"

# --- __builtins__ subscript bypass ---
run_test_both ask "python3 -c '__builtins__[\"open\"](\"/tmp/x\",\"w\").write(\"x\")'" \
  "escape: __builtins__ subscript"
run_test_both ask "python3 -c '__builtins__.eval(\"1+1\")'" \
  "escape: __builtins__ attribute"
run_test_both ask "python3 -c 'b = __builtins__; b[\"exec\"](\"x\")'" \
  "escape: __builtins__ rebind"

# --- bare dunder Name reads ---
run_test_both ask "python3 -c 'print(__loader__)'" \
  "escape: __loader__ Name read"
run_test_both ask "python3 -c 'print(__spec__)'" \
  "escape: __spec__ Name read"
run_test_both ask "python3 -c 'print(__package__)'" \
  "escape: __package__ Name read"
run_test_both ask "python3 -c 'fn = __import__'" \
  "escape: __import__ rebind to Name"

# --- sys attribute escapes ---
run_test_both ask "python3 -c 'import sys; sys.path.insert(0, \"/evil\")'" \
  "escape: sys.path mutation"
run_test_both ask "python3 -c 'import sys; sys.meta_path.insert(0, x)'" \
  "escape: sys.meta_path mutation"
run_test_both ask "python3 -c 'import sys; f = sys._getframe(0); print(f.f_globals)'" \
  "escape: sys._getframe stack walk"
run_test_both ask "python3 -c 'import sys; sys.settrace(lambda *a: a)'" \
  "escape: sys.settrace"
run_test_both ask "python3 -c 'import sys; sys.addaudithook(lambda *a: None)'" \
  "escape: sys.addaudithook"

# --- io low-level write bypasses ---
run_test_both ask "python3 -c 'import io; io.FileIO(\"/tmp/x\", \"w\").write(b\"pwned\")'" \
  "escape: io.FileIO write mode"
run_test_both ask "python3 -c 'import io; io.FileIO(\"/tmp/x\", mode=\"wb\")'" \
  "escape: io.FileIO mode kwarg"
run_test_both ask "python3 -c 'import io; io.FileIO(\"/tmp/x\", \"a\")'" \
  "escape: io.FileIO append mode"
run_test_both ask "python3 -c 'import io; io.BufferedWriter(raw)'" \
  "escape: io.BufferedWriter wrapper"
run_test_both ask "python3 -c 'import io; io.BufferedRandom(raw)'" \
  "escape: io.BufferedRandom wrapper"
run_test_both ask "python3 -c 'from io import FileIO
FileIO(\"/tmp/x\", \"w\")'" \
  "escape: from io import FileIO (rebind)"
run_test_both ask "python3 -c 'from io import open as o
o(\"/tmp/x\", \"w\")'" \
  "escape: from io import open as o"

# --- aliased dangerous imports ---
run_test_both ask "python3 -c 'import os as o; o.system(\"id\")'" \
  "escape: import os as alias"
run_test_both ask "python3 -c 'import subprocess as s; s.run([\"id\"])'" \
  "escape: import subprocess as alias"

# --- dunder-attribute traversal escapes ---
run_test_both ask "python3 -c '().__class__.__bases__[0].__subclasses__()'" \
  "escape: tuple class subclasses traversal"
run_test_both ask "python3 -c '\"\".__class__.__mro__[-1].__subclasses__()'" \
  "escape: str class mro traversal"
run_test_both ask "python3 -c 'type([]).__bases__'" \
  "escape: type().__bases__"
run_test_both ask "python3 -c 'def f(): pass
print(f.__globals__)'" \
  "escape: function.__globals__"
run_test_both ask "python3 -c 'def f(): pass
print(f.__code__)'" \
  "escape: function.__code__"

# --- code execution primitives ---
run_test_both ask "python3 -c 'exec(\"import os; os.system(\\\"id\\\")\")'" \
  "escape: exec() builtin"
run_test_both ask "python3 -c 'eval(\"1+1\")'" \
  "escape: eval() builtin"
run_test_both ask "python3 -c 'compile(\"x\", \"<s>\", \"exec\")'" \
  "escape: compile() builtin"
run_test_both ask "python3 -c '__import__(\"os\").system(\"id\")'" \
  "escape: __import__() bare call"
run_test_both ask "python3 -c 'getattr(some, \"x\")'" \
  "escape: getattr() builtin"
run_test_both ask "python3 -c 'setattr(some, \"x\", y)'" \
  "escape: setattr() builtin"
run_test_both ask "python3 -c 'globals()[\"x\"] = 1'" \
  "escape: globals() builtin"
run_test_both ask "python3 -c 'vars()[\"x\"] = 1'" \
  "escape: vars() builtin"

# --- write-mode open() in many forms ---
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"w\")'" \
  "escape: open w"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"a\")'" \
  "escape: open a"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"x\")'" \
  "escape: open x (exclusive create)"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"r+\")'" \
  "escape: open r+"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"w+\")'" \
  "escape: open w+"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"a+\")'" \
  "escape: open a+"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"wb\")'" \
  "escape: open wb"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"ab\")'" \
  "escape: open ab"
run_test_both ask "python3 -c 'open(\"/tmp/x\", \"xb\")'" \
  "escape: open xb"
run_test_both ask "python3 -c 'open(\"/tmp/x\", mode)'" \
  "escape: open mode non-literal"
run_test_both ask "python3 -c 'mode=\"w\"; open(\"/tmp/x\", mode)'" \
  "escape: open mode via variable"

# --- banned-module imports across all categories ---
run_test_both ask "python3 -c 'import os'" \
  "escape: import os"
run_test_both ask "python3 -c 'import subprocess'" \
  "escape: import subprocess"
run_test_both ask "python3 -c 'import socket'" \
  "escape: import socket"
run_test_both ask "python3 -c 'import urllib.request'" \
  "escape: import urllib.request"
run_test_both ask "python3 -c 'import http.client'" \
  "escape: import http.client"
run_test_both ask "python3 -c 'import ftplib'" \
  "escape: import ftplib"
run_test_both ask "python3 -c 'import smtplib'" \
  "escape: import smtplib"
run_test_both ask "python3 -c 'import asyncio'" \
  "escape: import asyncio"
run_test_both ask "python3 -c 'import shutil; shutil.rmtree(\"/tmp/x\")'" \
  "escape: import shutil"
run_test_both ask "python3 -c 'import pickle; pickle.loads(b\"\")'" \
  "escape: import pickle (RCE on load)"
run_test_both ask "python3 -c 'import marshal; marshal.loads(b\"\")'" \
  "escape: import marshal"
run_test_both ask "python3 -c 'import shelve'" \
  "escape: import shelve"
run_test_both ask "python3 -c 'import ctypes; ctypes.CDLL(\"libc.so.6\")'" \
  "escape: import ctypes (load shared lib)"
run_test_both ask "python3 -c 'import multiprocessing'" \
  "escape: import multiprocessing"
run_test_both ask "python3 -c 'import threading'" \
  "escape: import threading"
run_test_both ask "python3 -c 'import importlib; importlib.import_module(\"os\")'" \
  "escape: import importlib"
run_test_both ask "python3 -c 'import tempfile; tempfile.mkstemp()'" \
  "escape: import tempfile (creates file)"
run_test_both ask "python3 -c 'from pathlib import Path; Path(\"/tmp/x\").write_text(\"y\")'" \
  "escape: pathlib write_text"
run_test_both ask "python3 -c 'from pathlib import Path; Path(\"/tmp/x\").touch()'" \
  "escape: pathlib touch"
run_test_both ask "python3 -c 'from pathlib import Path; Path(\"/tmp/x\").unlink()'" \
  "escape: pathlib unlink"
run_test_both ask "python3 -c 'import pty; pty.spawn(\"/bin/sh\")'" \
  "escape: import pty (spawn shell)"
run_test_both ask "python3 -c 'import xmlrpc.client'" \
  "escape: import xmlrpc.client"

# --- code embedded in expressions / statements that ast.walk must reach ---
run_test_both ask "python3 -c '(lambda: __import__(\"os\"))()'" \
  "escape: lambda body w/ __import__"
run_test_both ask "python3 -c '[exec(x) for x in [1]]'" \
  "escape: exec inside list comprehension"
run_test_both ask "python3 -c '{k: __import__(\"os\") for k in [1]}'" \
  "escape: __import__ in dict comprehension"
run_test_both ask "python3 -c '(__import__(\"os\") for x in [1])'" \
  "escape: __import__ in generator"
run_test_both ask "python3 -c '(x := __import__(\"os\"))'" \
  "escape: walrus assignment"
run_test_both ask "python3 -c 'def f(x=__import__(\"os\")): pass'" \
  "escape: __import__ in default arg"
run_test_both ask "python3 -c 'try:
    import os
except: pass'" \
  "escape: import os inside try"
run_test_both ask "python3 -c 'class X:
    import os'" \
  "escape: import os inside class body"
run_test_both ask "python3 -c 'def f():
    import os
    os.system(\"id\")'" \
  "escape: import os inside function body"
run_test_both ask "python3 -c 'async def f():
    import os'" \
  "escape: import os inside async function"
run_test_both ask "python3 -c 'match x:
    case _:
        __import__(\"os\")'" \
  "escape: __import__ inside match-case"

# --- relative imports / wildcard in unsafe modules ---
run_test_both ask "python3 -c 'from io import *'" \
  "escape: wildcard import from io"

# --- agent-discovered escapes (from sandbox-escape research, Apr 2026) ---
# Each was verified to: (a) actually obtain process exec / file write / etc.
# at runtime, AND (b) initially pass an earlier version of the static check.

# Open aliasing — `f = open; f(p, "w")` defeats the call-site mode check
run_test_both ask "python3 -c '_o = open; _o(\"/tmp/x\",\"w\").write(\"x\")'" \
  "agent-A1: open aliased via assignment"
run_test_both ask "python3 -c 'import functools
functools.partial(open, mode=\"w\")(\"/tmp/x\").write(\"x\")'" \
  "agent-A2: functools.partial(open, mode=w)"
run_test_both ask "python3 -c 'fs = {\"w\": open}; fs[\"w\"](\"/tmp/x\",\"w\").write(\"x\")'" \
  "agent-A3: open stored in dict"
# io alias defeats name-based io.open mode check
run_test_both ask "python3 -c 'import io as _io; _io.open(\"/tmp/x\",\"w\").write(\"x\")'" \
  "agent-A4: import io as alias (io.open bypass)"
run_test_both ask "python3 -c 'import io as _io; _io.FileIO(\"/tmp/x\",\"w\").write(b\"x\")'" \
  "agent-A5: io.FileIO via aliased io"

# codecs as a write path
run_test_both ask "python3 -c 'import codecs; codecs.open(\"/tmp/x\",\"w\").write(\"x\")'" \
  "agent-B1: codecs.open() write mode"
run_test_both ask "python3 -c 'import codecs; codecs.builtins.open(\"/tmp/x\",\"w\")'" \
  "agent-B2: codecs.builtins.open"
run_test_both ask "python3 -c 'import json; json.codecs.open(\"/tmp/x\",\"w\")'" \
  "agent-B3: json.codecs.open"

# os reachable via path/utility modules
run_test_both ask "python3 -c 'import os.path; os.system(\"id\")'" \
  "agent-C1: import os.path binds os namespace"
run_test_both ask "python3 -c 'import posixpath; posixpath.os.system(\"id\")'" \
  "agent-C2: posixpath.os.system"
run_test_both ask "python3 -c 'import ntpath; ntpath.os.system(\"id\")'" \
  "agent-C3: ntpath.os.system"
run_test_both ask "python3 -c 'import genericpath; genericpath.os.system(\"id\")'" \
  "agent-C4: genericpath.os.system"
run_test_both ask "python3 -c 'import uuid; uuid.os.system(\"id\")'" \
  "agent-C5: uuid.os.system"
run_test_both ask "python3 -c 'from xml.sax.saxutils import os
os.system(\"id\")'" \
  "agent-C6: from xml.sax.saxutils import os"
run_test_both ask "python3 -c 'from posixpath import os
os.system(\"id\")'" \
  "agent-C7a: from posixpath import os"
run_test_both ask "python3 -c 'from os.path import os
os.system(\"id\")'" \
  "agent-C7b: from os.path import os"
run_test_both ask "python3 -c 'from genericpath import os
os.system(\"id\")'" \
  "agent-C7c: from genericpath import os"
run_test_both ask "python3 -c 'import posixpath; posixpath.os.fdopen(0,\"w\")'" \
  "agent-C8: posixpath.os.fdopen"

# sys reachability via alias / transitive attribute
run_test_both ask "python3 -c 'import sys as s; s.modules[\"os\"].system(\"id\")'" \
  "agent-D1: import sys as alias"
run_test_both ask "python3 -c 'import codecs; codecs.sys.modules[\"os\"].system(\"id\")'" \
  "agent-D2a: codecs.sys.modules"
run_test_both ask "python3 -c 'import statistics; statistics.sys.modules[\"os\"].system(\"id\")'" \
  "agent-D2b: statistics.sys.modules"
run_test_both ask "python3 -c 'import uuid; uuid.sys.modules[\"os\"].system(\"id\")'" \
  "agent-D2c: uuid.sys.modules"
run_test_both ask "python3 -c 'import xml.etree.ElementTree as ET
ET.sys.modules[\"os\"].system(\"id\")'" \
  "agent-D2d: ET.sys.modules"

# builtins reachable via reprlib
run_test_both ask "python3 -c 'import reprlib; reprlib.builtins.open(\"/tmp/x\",\"w\").write(\"x\")'" \
  "agent-E1: reprlib.builtins.open"

# operator/functools indirection
run_test_both ask "python3 -c 'import operator, posixpath
operator.attrgetter(\"os\")(posixpath).system(\"id\")'" \
  "agent-F1: operator.attrgetter dispatch"
run_test_both ask "python3 -c 'import functools, posixpath
functools.partial(posixpath.os.system, \"id\")()'" \
  "agent-F2: functools.partial deferred call"

# --- additional bypasses found by introspection scan of allowed modules ---
run_test_both ask "python3 -c 'import enum; enum.bltns.open(\"/tmp/x\",\"w\")'" \
  "scan: enum.bltns is alias for builtins"
run_test_both ask "python3 -c 'from enum import bltns
bltns.open(\"/tmp/x\",\"w\")'" \
  "scan: from enum import bltns"
run_test_both ask "python3 -c 'import queue; queue.threading.Thread(target=print)'" \
  "scan: queue.threading"
run_test_both ask "python3 -c 'from queue import threading
threading.Thread()'" \
  "scan: from queue import threading"
run_test_both ask "python3 -c 'import xml.sax.saxutils as x
x.urllib.request.urlopen(\"http://x\")'" \
  "scan: xml.sax.saxutils.urllib"
run_test_both ask "python3 -c 'from xml.sax.saxutils import urllib
urllib.request.urlopen(\"http://x\")'" \
  "scan: from xml.sax.saxutils import urllib"
run_test_both ask "python3 -c 'import codecs as c
c.open(\"/tmp/x\",\"w\")'" \
  "scan: import codecs as alias"
run_test_both ask "python3 -c 'from json import codecs
codecs.open(\"/tmp/x\",\"w\")'" \
  "scan: from json import codecs"
run_test_both ask "python3 -c 'from collections.abc import sys'" \
  "scan: from collections.abc import sys"

# --- agent-discovered bash-level escapes (shfmt parser tricks, Apr 2026) ---

# Bypass-4: xml.etree.ElementTree.write() writes arbitrary files
run_test_both ask "python3 -c 'import xml.etree.ElementTree as ET
ET.ElementTree(ET.Element(\"r\")).write(\"/tmp/x\")'" \
  "agent-bash-4: ET.write to disk"
run_test_both ask "python3 -c 'import xml.dom.minidom; xml.dom.minidom.parseString(\"<r/>\").writexml(open(\"/tmp/x\",\"w\"))'" \
  "agent-bash-4b: xml.dom.minidom.writexml"

# Bypass-5: python -m json.tool with outfile writes to disk
run_test_both none 'python3 -m json.tool /tmp/in /tmp/out' \
  "agent-bash-5: -m json.tool with outfile (no longer safe-listed)"
run_test_both none 'python3 -m json.tool' \
  "agent-bash-5b: -m json.tool standalone (also no longer safe-listed)"

# Bypass-6: env-var prefix smuggles import path / preload
run_test_both none "PYTHONPATH=/tmp python3 -c 'import json'" \
  "agent-bash-6a: PYTHONPATH= prefix"
run_test_both none "PYTHONSTARTUP=/tmp/evil.py python3 -c 'import json'" \
  "agent-bash-6b: PYTHONSTARTUP= prefix"
run_test_both none "LD_PRELOAD=/tmp/evil.so python3 -c 'import json'" \
  "agent-bash-6c: LD_PRELOAD= prefix"

# Bypass-7: env wrapper
run_test_both none "env python3 -c 'import os; os.system(\"id\")'" \
  "agent-bash-7a: env wraps python (must abstain)"
run_test_both none "env VAR=val python3 -c 'import os'" \
  "agent-bash-7b: env VAR=val wraps python"
run_test_both none "env -i python3 -c 'import os'" \
  "agent-bash-7c: env -i wraps python"

# env alone (no program) still allowed for env inspection
run_test_both allow "env" "env (no args) still allow"
run_test_both allow "env -i" "env -i (no program) still allow"

# ===== PASSTHROUGH: python forms classifier cannot validate =====
echo "── python passthrough (no opinion) ──"
run_test_both none 'python3 -c "$(cat foo.py)"' \
  "python -c with command substitution"
run_test_both none 'python3 -c "${CODE}"' \
  "python -c with parameter expansion"
run_test_both none "python3 myscript.py" \
  "python script file"
run_test_both none "python3 -c 'import json' && cat foo" \
  "python -c compound"
run_test_both none "python3 -c 'import json' | jq ." \
  "python -c piped"
run_test_both none "cat x.py | python3 -c 'print(1)'" \
  "command piped to python -c"
run_test_both none "python3 -m timeit '1+1'" \
  "python -m unsafe module"
run_test_both none "/usr/bin/python3 -c 'import json'" \
  "python via absolute path"
run_test_both none 'python3 -uc "import json"' \
  "python combined short flags"
# ANSI-C quoted ($'...') — bash decodes \n/\x at runtime, so what we read
# statically may differ from what runs. Always abstain to avoid the gap.
run_test_both none $'python3 -c $\'import json\\nprint(1)\'' \
  "python -c with ANSI-C \$'...' quoting"
run_test_both none $'python3 -c $\'\\x69mport os\\nos.system(\"id\")\'' \
  "ANSI-C escape: \\x-encoded import (must abstain)"

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
run_test_both allow "uv help"
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
run_test_both ask "uv pip uninstall flask"
run_test_both allow "uv pip compile requirements.in"
run_test_both allow "uv pip sync requirements.txt"
run_test_both allow "uv python install 3.12"
run_test_both allow "uv python uninstall 3.11"
run_test_both allow "uv python pin 3.12"
run_test_both none "uv tool run ruff check ." "uv tool run (passthrough, alias for uvx)"

# ===== ASK: uv global tool operations =====
echo "── uv global tool operations ──"
run_test_both ask "uv tool install ruff"
run_test_both ask "uv tool uninstall ruff"
run_test_both ask "uv tool upgrade ruff"

# ===== ALLOW: uv with global flags =====
echo "── uv with global flags ──"
run_test_both allow "uv --quiet sync" "uv --quiet sync"
run_test_both allow "uv --no-cache pip list" "uv --no-cache pip list"
run_test_both allow "uv --directory /tmp/myproject tree" "uv --directory <path> tree"

# ===== PASSTHROUGH: uv run --with =====
echo "── uv run --with (passthrough) ──"
run_test_both none "uv run --with requests script.py" "uv run --with (passthrough)"
run_test_both none "uv run --with=requests script.py" "uv run --with= (passthrough)"

# ===== ASK: uv publish/destructive =====
echo "── uv publish/destructive ──"
run_test_both ask "uv publish"
run_test_both ask "uv unknown-subcommand" "uv unknown subcommand (catch-all)"
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
run_test_both none "wget https://example.com" "wget (passthrough)"
run_test_both none "make build" "make (passthrough)"
run_test_both none "rm -rf /tmp/test" "rm (passthrough)"

# ===== BOOTSTRAP BYPASS: setup-deps.sh allowed regardless of install path =====
# The dep check would otherwise block the very script that installs the deps.
# Claude Code installs plugins under a versioned path
# (.../permission-manager/<version>/scripts/setup-deps.sh), so the bypass must
# tolerate any path segment between "permission-manager" and the script name.
echo "── Bootstrap bypass: setup-deps.sh ──"
run_test_both allow "bash /home/u/.claude/plugins/cache/agent-toolkit/permission-manager/2.13.1/scripts/setup-deps.sh" "bootstrap: versioned cache path (Claude Code)"
run_test_both allow "bash ~/dev/agent-toolkit/plugins-claude/permission-manager/scripts/setup-deps.sh" "bootstrap: unversioned dev path"
run_test_both allow "bash /opt/copilot/plugins/permission-manager/scripts/setup-deps.sh" "bootstrap: copilot install path"

# ===== ALLOW-EDIT MODE TESTS =====
# Helper to construct payloads with permission_mode: acceptEdits
run_test_allow_edit() {
  local expected="$1" command="$2" label="${3:-$2}"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  local payload raw result
  payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(jq -Rn --arg c "$command" '$c')},\"permission_mode\":\"acceptEdits\"}")

  raw=$(echo "$payload" | bash "$HOOK_SCRIPT" 2>/dev/null)
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

# ===== ALLOW-EDIT: safe project-local writes =====
echo "── Allow-edit: safe project-local writes ──"
run_test_allow_edit allow "chmod +x scripts/foo.sh" "allow-edit: chmod +x scripts/foo.sh"
run_test_allow_edit allow "mkdir -p src/components" "allow-edit: mkdir -p src/components"
run_test_allow_edit allow "touch newfile.txt" "allow-edit: touch newfile.txt"

# ===== ALLOW-EDIT: paths outside project (passthrough) =====
echo "── Allow-edit: paths outside project (passthrough) ──"
run_test_allow_edit none "cp /etc/passwd ./leaked.txt" "allow-edit: cp source outside project"
run_test_allow_edit none "mv important.txt /tmp/gone.txt" "allow-edit: mv destination outside project"
run_test_allow_edit none "chmod +x /usr/local/bin/tool" "allow-edit: chmod target outside project"
run_test_allow_edit none "install -m 755 script.sh /usr/local/bin/" "allow-edit: install destination outside project"

# ===== ALLOW-EDIT: git promotions =====
echo "── Allow-edit: git promotions ──"
run_test_allow_edit allow "git pull" "allow-edit: git pull"
run_test_allow_edit allow "git merge feature-branch" "allow-edit: git merge"
run_test_allow_edit allow "git rebase main" "allow-edit: git rebase"
run_test_allow_edit allow "git stash" "allow-edit: git stash"
run_test_allow_edit allow "git stash pop" "allow-edit: git stash pop"

# ===== ALLOW-EDIT: not promoted (passthrough) =====
echo "── Allow-edit: not promoted (passthrough) ──"
run_test_allow_edit none "git cherry-pick abc123" "allow-edit: git cherry-pick (not promoted)"
run_test_allow_edit none "git clone https://github.com/foo/bar" "allow-edit: git clone (not promoted)"
run_test_allow_edit none "git rm file.txt" "allow-edit: git rm (not promoted)"

# ===== ALLOW-EDIT: still deny =====
echo "── Allow-edit: still deny ──"
run_test_allow_edit deny "git reset --hard" "allow-edit: git reset --hard (still deny)"
run_test_allow_edit deny "git clean -fd" "allow-edit: git clean (still deny)"
run_test_allow_edit deny "echo foo > bar.txt" "allow-edit: redirect (still deny)"

# ===== ALLOW-EDIT INACTIVE: same commands not promoted =====
echo "── Allow-edit inactive: no promotion ──"
run_test none "chmod +x scripts/foo.sh" "no allow-edit: chmod (passthrough)" "claude"
run_test ask "git pull" "no allow-edit: git pull (ask)" "claude"
run_test ask "git stash" "no allow-edit: git stash (ask)" "claude"

# ===== COMPOUND: unclassified segments passthrough =====
echo "── Compound: unclassified segments passthrough ──"
run_test_both none "cat foo.txt && unknown-tool bar" "compound: classified + unclassified → passthrough"

# ===== ALLOW-EDIT: custom config — empty list =====
echo "── Allow-edit: custom config ──"
_ae_tmpdir=$(mktemp -d)
_ae_empty_config="$_ae_tmpdir/allow-edit-empty.json"
echo '{"allow":[]}' >"$_ae_empty_config"

# Empty config: no allow-edit promotions
_ae_payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"chmod +x scripts/foo.sh\"},\"permission_mode\":\"acceptEdits\"}")
_ae_raw=$(echo "$_ae_payload" | ALLOW_EDIT_PERMISSIONS_GLOBAL="$_ae_empty_config" ALLOW_EDIT_PERMISSIONS_PROJECT="$_ae_tmpdir/nonexistent.json" bash "$HOOK_SCRIPT" 2>/dev/null)
if [[ -z "$_ae_raw" ]]; then
  _ae_result="none"
else
  _ae_result=$(echo "$_ae_raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
fi
if [[ "$_ae_result" == "none" ]]; then
  printf "  \033[32m✓\033[0m %-6s %s\n" "none" "allow-edit: empty config → no promotion"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "none" "allow-edit: empty config → no promotion" "$_ae_result"
  ((FAIL++)) || true
fi

# Restricted config: only chmod and mkdir
_ae_restricted_config="$_ae_tmpdir/allow-edit-restricted.json"
echo '{"allow":["chmod","mkdir"]}' >"$_ae_restricted_config"

# chmod should be promoted
_ae_payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"chmod +x scripts/foo.sh\"},\"permission_mode\":\"acceptEdits\"}")
_ae_raw=$(echo "$_ae_payload" | ALLOW_EDIT_PERMISSIONS_GLOBAL="$_ae_restricted_config" ALLOW_EDIT_PERMISSIONS_PROJECT="$_ae_tmpdir/nonexistent.json" bash "$HOOK_SCRIPT" 2>/dev/null)
if [[ -z "$_ae_raw" ]]; then
  _ae_result="none"
else
  _ae_result=$(echo "$_ae_raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
fi
if [[ "$_ae_result" == "allow" ]]; then
  printf "  \033[32m✓\033[0m %-6s %s\n" "allow" "allow-edit: restricted config → chmod promoted"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "allow" "allow-edit: restricted config → chmod promoted" "$_ae_result"
  ((FAIL++)) || true
fi

# touch should NOT be promoted (not in restricted list)
_ae_payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"touch newfile.txt\"},\"permission_mode\":\"acceptEdits\"}")
_ae_raw=$(echo "$_ae_payload" | ALLOW_EDIT_PERMISSIONS_GLOBAL="$_ae_restricted_config" ALLOW_EDIT_PERMISSIONS_PROJECT="$_ae_tmpdir/nonexistent.json" bash "$HOOK_SCRIPT" 2>/dev/null)
if [[ -z "$_ae_raw" ]]; then
  _ae_result="none"
else
  _ae_result=$(echo "$_ae_raw" | jq -r '.hookSpecificOutput.permissionDecision // "none"')
fi
if [[ "$_ae_result" == "none" ]]; then
  printf "  \033[32m✓\033[0m %-6s %s\n" "none" "allow-edit: restricted config → touch not promoted"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "none" "allow-edit: restricted config → touch not promoted" "$_ae_result"
  ((FAIL++)) || true
fi

rm -rf "$_ae_tmpdir"

# ===== AUDIT LOG: mode field =====
echo "── Audit log: mode field ──"
_log_tmpdir=$(mktemp -d)
_log_file="$_log_tmpdir/audit.jsonl"

# allow-edit mode entry
_log_payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git pull\"},\"permission_mode\":\"acceptEdits\"}")
echo "$_log_payload" | PERMISSION_AUDIT_LOG="$_log_file" bash "$HOOK_SCRIPT" >/dev/null 2>&1
_log_mode=$(tail -1 "$_log_file" | jq -r '.mode // "missing"')
if [[ "$_log_mode" == "allow-edit" ]]; then
  printf "  \033[32m✓\033[0m %-6s %s\n" "ok" "audit log: mode=allow-edit in allow-edits mode"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "fail" "audit log: mode=allow-edit in allow-edits mode" "$_log_mode"
  ((FAIL++)) || true
fi

# default mode entry
_log_payload=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git pull\"}}")
echo "$_log_payload" | PERMISSION_AUDIT_LOG="$_log_file" bash "$HOOK_SCRIPT" >/dev/null 2>&1
_log_mode=$(tail -1 "$_log_file" | jq -r '.mode // "missing"')
if [[ "$_log_mode" == "default" ]]; then
  printf "  \033[32m✓\033[0m %-6s %s\n" "ok" "audit log: mode=default in normal mode"
  ((PASS++)) || true
else
  printf "  \033[31m✗\033[0m %-6s %s  (got: %s)\n" "fail" "audit log: mode=default in normal mode" "$_log_mode"
  ((FAIL++)) || true
fi

rm -rf "$_log_tmpdir"

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
