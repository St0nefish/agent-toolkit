#!/usr/bin/env bash
# test-issue-write-json.sh — git-cli write-command JSON output (#142).
#
# Verifies that write commands emit parseable JSON instead of gh/tea human text:
#   - issue/pr create        -> {number, url}
#   - issue/pr comment (add) -> {id, author, body, html_url, created_at}
#   - issue comment list     -> [ {id, ...}, ... ]
#   - issue comment delete   -> {deleted: true, id}
#   - issue comment edit     -> {id, body, ...}
#   - api <path>             -> raw backend JSON passthrough
# Covers both the github (gh) and gitea (tea) platform paths via PATH-injected
# mock CLIs, mirroring tests/git-cli/test-run-show.sh.
#
# Usage: bash tests/git-cli/test-issue-write-json.sh [filter]

set -uo pipefail

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

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
# Returns 0 (skip) when a filter is set and does not match; counts the skip.
skip_filter() {
  if [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi
  return 1
}

run_cli() { PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" "$@" 2>"$MOCK_DIR/stderr"; }

# ---------------------------------------------------------------------------
# Shared mock backends. The gh/tea mocks answer the REST/CLI shapes the wrapper
# now uses. The git mock selects the platform via the remote hostname.
# ---------------------------------------------------------------------------

write_gh_mock() {
  cat >"$MOCK_DIR/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$1 $2" in
  "issue create") echo "https://github.com/owner/repo/issues/42"; exit 0 ;;
  "pr create")    echo "https://github.com/owner/repo/pull/7";    exit 0 ;;
esac
if [[ "$1" == "api" ]]; then
  case "$args" in
    *"api user"*) echo "alice"; exit 0 ;;
    *"-X DELETE"*) exit 0 ;;
    *"-X PATCH"*)  echo '{"id":101,"body":"edited","html_url":"https://github.com/owner/repo/issues/5#issuecomment-101","user":{"login":"alice"},"created_at":"2026-06-02T00:00:00Z"}'; exit 0 ;;
    *"-X POST"*comments*) echo '{"id":101,"body":"hello","html_url":"https://github.com/owner/repo/issues/5#issuecomment-101","user":{"login":"alice"},"created_at":"2026-06-02T00:00:00Z"}'; exit 0 ;;
    *comments*) echo '[{"id":101,"body":"first","html_url":"u1","user":{"login":"alice"},"created_at":"t1"},{"id":102,"body":"second","html_url":"u2","user":{"login":"bob"},"created_at":"t2"}]'; exit 0 ;;
    *__ping__*) echo '{"pong":true}'; exit 0 ;;
  esac
fi
echo "unexpected gh call: $args" >&2; exit 1
EOF
  chmod +x "$MOCK_DIR/gh"
}

write_tea_mock() {
  cat >"$MOCK_DIR/tea" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$1 $2 $3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech","user":"alice"}]'; exit 0 ;;
esac
case "$1 $2" in
  # Realistic tea output, not a synthetic one-liner: tea renders the whole
  # created object (title/author/body, indented) before a flush-left
  # confirmation URL. Decoy #1 (both cases): a markdown link to issue #1
  # embedded mid-body, mirroring how real tracker tickets link back to a
  # parent issue — the anchored regex alone rejects this (it's not a bare
  # URL line), so it also guards the pre-anchor fallback path. Decoy #2
  # (pr create): a *bare* URL on its own indented line, e.g. a "See <url>"
  # reference — this one DOES match the anchored "line is just a URL"
  # pattern, so only taking the *last* match (not first) tells it apart
  # from the true confirmation line that follows. Together these catch a
  # regression of the bug where emit_created_json grabbed the first
  # issue/pull URL anywhere in the output instead of the trailing
  # confirmation line, always reporting the linked issue's number (#1)
  # instead of the one actually created (#42 / #7).
  "issues create")
    printf '  # #42 x (open)\n\n  @alice created 2026-06-02\n\n  Child of [parent](https://git.stonefish.tech/owner/repo/issues/1).\n\nhttps://git.stonefish.tech/owner/repo/issues/42\n'
    exit 0 ;;
  "pr create")
    printf '  # #7 x (open)\n\n  @alice wants to merge\n\n  Fixes [parent](https://git.stonefish.tech/owner/repo/issues/1).\n\n  See also\n  https://git.stonefish.tech/owner/repo/issues/1\n\nhttps://git.stonefish.tech/owner/repo/pulls/7\n'
    exit 0 ;;
esac
if [[ "$1" == "api" ]]; then
  case "$args" in
    *"-X DELETE"*) exit 0 ;;
    *"-X PATCH"*)  echo '{"id":101,"body":"edited","html_url":"https://git.stonefish.tech/owner/repo/issues/5#issuecomment-101","user":{"login":"alice"},"created_at":"t"}'; exit 0 ;;
    *"-X POST"*comments*) echo '{"id":101,"body":"hello","html_url":"https://git.stonefish.tech/owner/repo/issues/5#issuecomment-101","user":{"login":"alice"},"created_at":"t"}'; exit 0 ;;
    *comments*) echo '[{"id":101,"body":"first","html_url":"u1","user":{"login":"alice"},"created_at":"t1"},{"id":102,"body":"second","html_url":"u2","user":{"login":"bob"},"created_at":"t2"}]'; exit 0 ;;
    *__ping__*) echo '{"pong":true}'; exit 0 ;;
  esac
fi
echo "unexpected tea call: $args" >&2; exit 1
EOF
  chmod +x "$MOCK_DIR/tea"
}

# Platform selectors: choose the remote host so detect_platform resolves
# github (github.com fallback) vs gitea (matches the tea login host).
set_platform_github() {
  cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://github.com/owner/repo.git" ;;
  *) command git "$@" ;;
esac
EOF
  chmod +x "$MOCK_DIR/git"
  # tea present but with a non-github login → no match → github.com fallback.
  cat >"$MOCK_DIR/tea" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "login list --output" ]] && { echo '[]'; exit 0; }
echo "unexpected tea call on github path: $*" >&2; exit 1
EOF
  chmod +x "$MOCK_DIR/tea"
  write_gh_mock
}

set_platform_gitea() {
  cat >"$MOCK_DIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "remote get-url origin") echo "https://git.stonefish.tech/owner/repo.git" ;;
  *) command git "$@" ;;
esac
EOF
  chmod +x "$MOCK_DIR/git"
  write_tea_mock
}

# assert_json <label> <jq-test-expr> <output>
assert_json() {
  local label="$1" expr="$2" out="$3"
  if ! echo "$out" | jq -e . >/dev/null 2>&1; then
    fail "$label" "not valid JSON: out=$out stderr=$(cat "$MOCK_DIR/stderr")"
  elif [[ "$(
    echo "$out" | jq -e "$expr" >/dev/null 2>&1
    echo $?
  )" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "assertion '$expr' failed: out=$out"
  fi
}

# ---------------------------------------------------------------------------
# Per-platform test battery
# ---------------------------------------------------------------------------

run_battery() {
  local plat="$1"
  echo "── write-command JSON: $plat ──"

  local label out rc

  label="[$plat] issue create -> {number,url}"
  if ! skip_filter "$label"; then
    out=$(run_cli issue create --title "x" --body "b") || true
    assert_json "$label" '.number == 42 and (.url | test("/issues/42$"))' "$out"
  fi

  label="[$plat] issue comment add -> {id,author,body}"
  if ! skip_filter "$label"; then
    out=$(run_cli issue comment 5 --body "hello") || true
    assert_json "$label" '.id == 101 and .author == "alice" and .body == "hello"' "$out"
  fi

  label="[$plat] issue comment list -> [{id},...]"
  if ! skip_filter "$label"; then
    out=$(run_cli issue comment list 5) || true
    assert_json "$label" '(type == "array") and (length == 2) and (.[0].id == 101)' "$out"
  fi

  label="[$plat] issue comment delete -> {deleted,id}"
  if ! skip_filter "$label"; then
    out=$(run_cli issue comment delete 99) || true
    assert_json "$label" '.deleted == true and .id == 99' "$out"
  fi

  label="[$plat] issue comment edit -> {id,body}"
  if ! skip_filter "$label"; then
    out=$(run_cli issue comment edit 101 --body "edited") || true
    assert_json "$label" '.id == 101 and .body == "edited"' "$out"
  fi

  label="[$plat] pr create -> {number,url}"
  if ! skip_filter "$label"; then
    out=$(run_cli pr create --title "x" --head feat --base main --body "b") || true
    assert_json "$label" '.number == 7 and (.url | test("/(pull|pulls)/7$"))' "$out"
  fi

  label="[$plat] pr comment add -> {id,body}"
  if ! skip_filter "$label"; then
    out=$(run_cli pr comment 5 --body "hello") || true
    assert_json "$label" '.id == 101 and .body == "hello"' "$out"
  fi

  label="[$plat] api passthrough -> raw backend JSON"
  if ! skip_filter "$label"; then
    out=$(run_cli api "repos/{owner}/{repo}/__ping__") || true
    assert_json "$label" '.pong == true' "$out"
  fi

  label="[$plat] api rejects leading flag (path must come first)"
  if ! skip_filter "$label"; then
    rc=0
    run_cli api -X GET >/dev/null || rc=$?
    if [[ "$rc" == "1" ]]; then pass "$label"; else fail "$label" "exit=$rc"; fi
  fi
}

set_platform_github
run_battery "github"
set_platform_gitea
run_battery "gitea"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
