#!/usr/bin/env bash
# test-pr-show-gitea.sh — Test harness for git-cli `pr show` on the Gitea path.
# Regression test for #140: the old code sourced from `tea pr list`, whose JSON
# omits the `merged` boolean and `merged_at` timestamp and emits `mergeable` as
# a string, so a merged PR reported merged:false / mergedAt:null and consumers
# thought it was still open. The fix fetches the PR detail via
# `tea api repos/{owner}/{repo}/pulls/<n>` and derives the merge fields from it.
#
# Uses mock git/tea scripts via PATH injection.
#
# Usage: bash tests/git-cli/test-pr-show-gitea.sh [filter]

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

SENTINEL="$MOCK_DIR/.pr_list_called"

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

# Mock git: report a Gitea remote so platform detection resolves to "gitea".
cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://git.stonefish.tech/owner/repo.git" ;;
  *) command git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# Mock tea:
#  - login list   → advertise a login for the remote host (so platform == gitea)
#  - pr list       → MUST NOT be called by the fixed code; record a sentinel
#  - api .../pulls/7 → canned merged PR object (Gitea REST shape)
cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output")
    echo '[{"url":"https://git.stonefish.tech"}]'
    exit 0
    ;;
  "pr list --output")
    # Regression guard: the fixed pr:show must never shell out to this.
    touch "$SENTINEL"
    echo '[]'
    exit 0
    ;;
esac
case "\$1:\$2" in
  api:repos/{owner}/{repo}/pulls/7)
    cat <<'JSON'
{
  "number": 7,
  "title": "Add widget",
  "body": "body text",
  "state": "closed",
  "merged": true,
  "merged_at": "2026-06-01T10:00:00Z",
  "mergeable": true,
  "user": {"login": "stonefish"},
  "head": {"ref": "feature-widget"},
  "base": {"ref": "master"},
  "labels": [{"name": "enhancement"}],
  "assignees": [{"login": "stonefish"}],
  "created_at": "2026-05-31T09:00:00Z",
  "updated_at": "2026-06-01T10:00:00Z",
  "html_url": "https://git.stonefish.tech/owner/repo/pulls/7"
}
JSON
    ;;
  *)
    echo "unexpected tea call: \$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_DIR/tea"

# ---------------------------------------------------------------------------
# Test: pr show emits reliable merge fields for a merged PR
# ---------------------------------------------------------------------------

echo "── pr show: Gitea REST merge fields (#140) ──"

label="pr show reports merged:true + merged_at for a merged PR"
if ! skip_filter "$label"; then
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr show 7 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")

  if [[ "$exit_code" != "0" ]]; then
    fail "$label" "exit=$exit_code stderr=$stderr"
  elif ! echo "$output" | jq -e . >/dev/null 2>&1; then
    fail "$label (valid JSON)" "output=$output stderr=$stderr"
  else
    errs=()
    [[ "$(echo "$output" | jq -r '.number')" == "7" ]] || errs+=("number != 7")
    [[ "$(echo "$output" | jq -r '.merged')" == "true" ]] || errs+=("merged != true")
    [[ "$(echo "$output" | jq -r '.merged | type')" == "boolean" ]] || errs+=("merged not a boolean")
    [[ "$(echo "$output" | jq -r '.merged_at')" == "2026-06-01T10:00:00Z" ]] || errs+=("merged_at wrong")
    [[ "$(echo "$output" | jq -r '.state')" == "merged" ]] || errs+=("state != merged (should derive from merged)")
    [[ "$(echo "$output" | jq -r '.mergeable')" == "true" ]] || errs+=("mergeable != true")
    [[ "$(echo "$output" | jq -r '.mergeable | type')" == "boolean" ]] || errs+=("mergeable not a boolean")
    [[ "$(echo "$output" | jq -r '.author')" == "stonefish" ]] || errs+=("author != stonefish")
    [[ "$(echo "$output" | jq -r '.head')" == "feature-widget" ]] || errs+=("head != feature-widget")
    [[ "$(echo "$output" | jq -r '.base')" == "master" ]] || errs+=("base != master")
    [[ "$(echo "$output" | jq -r '.labels[0]')" == "enhancement" ]] || errs+=("labels[0] != enhancement")
    [[ "$(echo "$output" | jq -r '.assignees[0]')" == "stonefish" ]] || errs+=("assignees[0] != stonefish")
    [[ "$(echo "$output" | jq -r '.url')" == "https://git.stonefish.tech/owner/repo/pulls/7" ]] || errs+=("url wrong")

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
# Test: regression guard — `tea pr list` is never invoked
# ---------------------------------------------------------------------------

label="pr show does not call 'tea pr list'"
if ! skip_filter "$label"; then
  if [[ -f "$SENTINEL" ]]; then
    fail "$label" "sentinel present — old list-based path was used"
  else
    pass "$label"
  fi
fi

# ---------------------------------------------------------------------------
# Test: an open (not merged) PR reports merged:false and keeps its real state
# ---------------------------------------------------------------------------

label="pr show: open PR reports merged:false, state:open"
if ! skip_filter "$label"; then
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "\$1:\$2" in
  api:repos/{owner}/{repo}/pulls/7)
    cat <<'JSON'
{
  "number": 7, "title": "WIP", "body": "", "state": "open",
  "merged": false, "merged_at": null, "mergeable": true,
  "user": {"login": "stonefish"}, "head": {"ref": "wip-x"}, "base": {"ref": "master"},
  "labels": [], "assignees": [],
  "created_at": "2026-05-31T09:00:00Z", "updated_at": "2026-05-31T09:00:00Z",
  "html_url": "https://git.stonefish.tech/owner/repo/pulls/7"
}
JSON
    ;;
  *) echo "unexpected tea call: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"

  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr show 7 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")
  if [[ "$exit_code" != "0" ]]; then
    fail "$label" "exit=$exit_code stderr=$stderr"
  else
    errs=()
    [[ "$(echo "$output" | jq -r '.merged')" == "false" ]] || errs+=("merged != false")
    [[ "$(echo "$output" | jq -r '.merged_at')" == "null" ]] || errs+=("merged_at != null")
    [[ "$(echo "$output" | jq -r '.state')" == "open" ]] || errs+=("state != open")
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
# Test: REST fetch failure → non-zero exit with helpful message
# ---------------------------------------------------------------------------

label="pr show: REST fetch failure → die"
if ! skip_filter "$label"; then
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "\$1:\$2" in
  api:repos/{owner}/{repo}/pulls/7) echo "404 Not Found" >&2; exit 1 ;;
  *) echo "unexpected tea call: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"

  exit_code=0
  PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" pr show 7 >/dev/null 2>"$MOCK_DIR/stderr" || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")
  if [[ "$exit_code" == "1" ]] && echo "$stderr" | grep -q "pulls/7 failed"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$stderr"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
