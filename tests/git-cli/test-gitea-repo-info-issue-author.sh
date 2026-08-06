#!/usr/bin/env bash
# test-gitea-repo-info-issue-author.sh — regression tests for two Gitea-path
# defects in git-cli, both caused by asking `tea` for a shape it does not emit.
#
#  1. `repo info` filtered `tea repos list --output json` on `.full_name`, but
#     that command emits only {owner,name,type,ssh}. The select never matched,
#     so the command always printed nothing and exited 0. It is also paginated
#     (30/page) and cannot report default_branch at all. Fixed by fetching the
#     repo directly via `tea api repos/{owner}/{repo}` — same shape as #133.
#
#  2. The remote_slug regex `([^/]+/[^/]+?)(\.git)?$` relied on a lazy
#     quantifier. POSIX ERE has none, so `+?` matched greedily, `(\.git)?`
#     matched empty, and the slug kept its ".git" suffix — which would have
#     404'd the new API call.
#
#  3. `issue list` requested --fields without `author`, while the normalizer
#     read `.author`. tea emits only the fields named, so author was always "".
#
# Uses mock git/tea scripts via PATH injection.
#
# Usage: bash tests/git-cli/test-gitea-repo-info-issue-author.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_CLI="$SCRIPT_DIR/../../utils/git-cli"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

MOCK_DIR=""
cleanup() { [[ -n "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"; }
trap cleanup EXIT
MOCK_DIR=$(mktemp -d)

# Mocks communicate back to the test through these files.
export GIT_CLI_TEST_REMOTE="$MOCK_DIR/remote_url" # git mock reads the URL here
export GIT_CLI_TEST_SENTINEL="$MOCK_DIR/repos_list_called"
export GIT_CLI_TEST_API_PATH="$MOCK_DIR/api_path"    # tea mock records the path asked for
export GIT_CLI_TEST_FIELDS="$MOCK_DIR/issues_fields" # tea mock records --fields

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}

skip_filter() {
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

# ---------------------------------------------------------------------------
# Mocks
# ---------------------------------------------------------------------------

# Mock git: report whatever remote URL the current test wrote, so platform
# detection resolves to "gitea" and the slug regex sees a realistic URL.
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") cat "$GIT_CLI_TEST_REMOTE" ;;
  *) command git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# Mock tea:
#  - login list  → advertise a login for the remote host (so platform == gitea)
#  - repos list  → MUST NOT be called by the fixed repo:info; record a sentinel
#                  and emit the real (insufficient) shape so the old filter,
#                  if reintroduced, still yields nothing
#  - api repos/<slug> → canned repo object; records the path it was asked for
#  - issues list → honours --fields the way tea does: emit ONLY those fields
cat >"$MOCK_DIR/tea" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "login list --output")
    echo '[{"url":"https://git.stonefish.tech"}]'
    exit 0
    ;;
  "repos list --output")
    touch "$GIT_CLI_TEST_SENTINEL"
    echo '[{"owner":"owner","name":"repo","type":"source","ssh":"ssh://git@git.stonefish.tech:2222/owner/repo.git"}]'
    exit 0
    ;;
esac

if [[ "$1" == "api" ]]; then
  printf '%s' "$2" >"$GIT_CLI_TEST_API_PATH"
  if [[ "$2" != "repos/owner/repo" ]]; then
    echo "404 Not Found: $2" >&2
    exit 1
  fi
  cat <<'JSON'
{
  "name": "repo",
  "full_name": "owner/repo",
  "owner": {"login": "owner"},
  "description": "a test repo",
  "default_branch": "trunk",
  "private": true,
  "html_url": "https://git.stonefish.tech/owner/repo",
  "stars_count": 7,
  "forks_count": 3
}
JSON
  exit 0
fi

if [[ "$1 $2" == "issues list" ]]; then
  fields=""
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "--fields" ]] && fields="$2"
    shift
  done
  printf '%s' "$fields" >"$GIT_CLI_TEST_FIELDS"
  # tea emits only the requested fields — mirror that faithfully.
  jq -nc --arg f "$fields" '
    ($f | split(",")) as $keys
    | [ {index: "42", title: "a bug", body: "", state: "open", author: "octocat",
         labels: [], milestone: "", comments: "0", created: "2026-01-01T00:00:00Z",
         updated: "2026-01-01T00:00:00Z", assignees: [], url: "https://x/42"}
        | with_entries(select(.key | IN($keys[]))) ]'
  exit 0
fi

echo "unexpected tea call: $*" >&2
exit 1
EOF
chmod +x "$MOCK_DIR/tea"

echo "ssh://git@git.stonefish.tech:2222/owner/repo.git" >"$GIT_CLI_TEST_REMOTE"

# ---------------------------------------------------------------------------
# Test: repo info returns a populated, normalized object
# ---------------------------------------------------------------------------

echo "── repo info: Gitea REST path ──"

label="repo info emits populated normalized JSON"
if ! skip_filter "$label"; then
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" repo info 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")

  if [[ "$exit_code" != "0" ]]; then
    fail "$label" "exit=$exit_code stderr=$stderr"
  elif ! echo "$output" | jq -e . >/dev/null 2>&1; then
    fail "$label (valid JSON)" "output=$output stderr=$stderr"
  else
    errs=()
    [[ "$(echo "$output" | jq -r '.name')" == "repo" ]] || errs+=("name != repo")
    [[ "$(echo "$output" | jq -r '.owner')" == "owner" ]] || errs+=("owner != owner (needs .owner.login)")
    [[ "$(echo "$output" | jq -r '.description')" == "a test repo" ]] || errs+=("description wrong")
    [[ "$(echo "$output" | jq -r '.default_branch')" == "trunk" ]] || errs+=("default_branch != trunk")
    [[ "$(echo "$output" | jq -r '.visibility')" == "private" ]] || errs+=("visibility != private")
    [[ "$(echo "$output" | jq -r '.url')" == "https://git.stonefish.tech/owner/repo" ]] || errs+=("url wrong")
    [[ "$(echo "$output" | jq -r '.stars')" == "7" ]] || errs+=("stars != 7")
    [[ "$(echo "$output" | jq -r '.forks')" == "3" ]] || errs+=("forks != 3")

    if [[ ${#errs[@]} -eq 0 ]]; then
      pass "$label"
    else
      fail "$label" "$(
        IFS='; '
        echo "${errs[*]}"
      ); output=$output"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Test: regression guard — `tea repos list` is never invoked
# ---------------------------------------------------------------------------

label="repo info does not call 'tea repos list'"
if ! skip_filter "$label"; then
  if [[ -f "$GIT_CLI_TEST_SENTINEL" ]]; then
    fail "$label" "sentinel present — old repos-list path was used"
  else
    pass "$label"
  fi
fi

# ---------------------------------------------------------------------------
# Test: the .git suffix is stripped from the slug, across remote URL forms
# ---------------------------------------------------------------------------

echo "── repo info: remote slug parsing ──"

for remote in \
  "ssh://git@git.stonefish.tech:2222/owner/repo.git" \
  "git@git.stonefish.tech:owner/repo.git" \
  "https://git.stonefish.tech/owner/repo.git" \
  "https://git.stonefish.tech/owner/repo"; do

  label="slug strips .git — $remote"
  if ! skip_filter "$label"; then
    echo "$remote" >"$GIT_CLI_TEST_REMOTE"
    : >"$GIT_CLI_TEST_API_PATH"
    exit_code=0
    PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" repo info >/dev/null 2>"$MOCK_DIR/stderr" || exit_code=$?
    asked=$(cat "$GIT_CLI_TEST_API_PATH")

    if [[ "$asked" == "repos/owner/repo" && "$exit_code" == "0" ]]; then
      pass "$label"
    else
      fail "$label" "asked=$asked exit=$exit_code"
    fi
  fi
done

echo "ssh://git@git.stonefish.tech:2222/owner/repo.git" >"$GIT_CLI_TEST_REMOTE"

# ---------------------------------------------------------------------------
# Test: issue list requests and reports the author
# ---------------------------------------------------------------------------

echo "── issue list: author field ──"

label="issue list requests 'author' in --fields"
if ! skip_filter "$label"; then
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" issue list 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")
  fields=$(cat "$GIT_CLI_TEST_FIELDS")

  if [[ "$exit_code" != "0" ]]; then
    fail "$label" "exit=$exit_code stderr=$stderr"
  elif [[ ",$fields," != *",author,"* ]]; then
    fail "$label" "--fields lacked author: $fields"
  else
    pass "$label"
  fi

  label="issue list reports a non-empty author"
  if ! skip_filter "$label"; then
    author=$(echo "$output" | jq -r '.[0].author // ""')
    if [[ "$author" == "octocat" ]]; then
      pass "$label"
    else
      fail "$label" "author='$author' output=$output"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
