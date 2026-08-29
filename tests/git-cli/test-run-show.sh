#!/usr/bin/env bash
# test-run-show.sh — Test harness for git-cli `run show` on the Gitea path.
# Regression test for #133: `tea actions runs view --output json` emits a human
# key/value table (not JSON) in tea 0.14.1, so the old code fed non-JSON to jq
# and died with "parse error: Invalid numeric literal". The fix fetches the run
# via `tea api repos/{owner}/{repo}/actions/runs/<id>` instead.
#
# Uses mock git/tea scripts via PATH injection.
#
# Usage: bash tests/git-cli/test-run-show.sh [filter]

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

SENTINEL="$MOCK_DIR/.runs_view_called"

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
  *) PATH=${PATH#"${0%/*}":}; exec git "$@" ;;
esac
EOF
chmod +x "$MOCK_DIR/git"

# Mock tea:
#  - login list  → advertise a login for the remote host (so platform == gitea)
#  - actions runs view → MUST NOT be called by the fixed code; record a sentinel
#  - api .../runs/<id>       → canned run object (REST shape, numeric id)
#  - api .../runs/<id>/jobs  → canned jobs payload
cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output")
    echo '[{"url":"https://git.stonefish.tech"}]'
    exit 0
    ;;
  "actions runs view")
    # Regression guard: the fixed run:show must never shell out to this.
    touch "$SENTINEL"
    echo "Run ID: 1075"
    echo "Status: in_progress"
    exit 0
    ;;
esac
case "\$1:\$2" in
  api:repos/{owner}/{repo}/actions/runs/1075)
    cat <<'JSON'
{
  "id": 1075,
  "status": "completed",
  "conclusion": "success",
  "name": "CI",
  "head_branch": "feature-x",
  "event": "push",
  "run_started_at": "2026-05-30T12:00:00Z",
  "url": "https://git.stonefish.tech/owner/repo/actions/runs/1075"
}
JSON
    ;;
  api:repos/{owner}/{repo}/actions/runs/1075/jobs)
    cat <<'JSON'
{"jobs":[
  {"id":1,"name":"build","status":"completed","conclusion":"success"},
  {"id":2,"name":"test","status":"completed","conclusion":"failure"}
]}
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
# Test: run show emits valid JSON with normalized fields
# ---------------------------------------------------------------------------

echo "── run show: Gitea REST path (#133) ──"

label="run show emits valid normalized JSON"
if ! skip_filter "$label"; then
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run show 1075 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")

  if [[ "$exit_code" != "0" ]]; then
    fail "$label" "exit=$exit_code stderr=$stderr"
  elif ! echo "$output" | jq -e . >/dev/null 2>&1; then
    fail "$label (valid JSON)" "output=$output stderr=$stderr"
  else
    errs=()
    [[ "$(echo "$output" | jq -r '.id')" == "1075" ]] || errs+=("id != \"1075\"")
    [[ "$(echo "$output" | jq -r '.id | type')" == "string" ]] || errs+=("id not a string")
    [[ "$(echo "$output" | jq -r '.status')" == "success" ]] || errs+=("status != success")
    [[ "$(echo "$output" | jq -r '.workflow')" == "CI" ]] || errs+=("workflow != CI")
    [[ "$(echo "$output" | jq -r '.branch')" == "feature-x" ]] || errs+=("branch != feature-x (head_branch)")
    [[ "$(echo "$output" | jq -r '.event')" == "push" ]] || errs+=("event != push")
    [[ "$(echo "$output" | jq -r '.started_at')" == "2026-05-30T12:00:00Z" ]] || errs+=("started_at wrong")
    [[ "$(echo "$output" | jq -r '.jobs | length')" == "2" ]] || errs+=("jobs length != 2")
    [[ "$(echo "$output" | jq -r '.jobs[1].status')" == "failure" ]] || errs+=("jobs[1].status != failure")

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
# Test: regression guard — `tea actions runs view` is never invoked
# ---------------------------------------------------------------------------

label="run show does not call 'tea actions runs view'"
if ! skip_filter "$label"; then
  if [[ -f "$SENTINEL" ]]; then
    fail "$label" "sentinel present — old code path was used"
  else
    pass "$label"
  fi
fi

# ---------------------------------------------------------------------------
# Test: REST fetch failure → non-zero exit with helpful message
# ---------------------------------------------------------------------------

label="run show: REST fetch failure → die"
if ! skip_filter "$label"; then
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "\$1:\$2" in
  api:repos/{owner}/{repo}/actions/runs/1075)
    echo "404 Not Found" >&2; exit 1 ;;
  api:repos/{owner}/{repo}/actions/runs/1075/jobs)
    echo '{"jobs":[]}' ;;
  *) echo "unexpected tea call: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"

  exit_code=0
  PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run show 1075 >/dev/null 2>"$MOCK_DIR/stderr" || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")
  if [[ "$exit_code" == "1" ]] && echo "$stderr" | grep -q "actions/runs/1075 failed"; then
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
