#!/usr/bin/env bash
# test-run-watch-gitea.sh — Test harness for git-cli `run watch` head-SHA
# fallback on the Gitea path.
#
# Regression test for #140: Gitea leaves head_branch/branch empty on
# pull_request-triggered runs, so `run list --branch` correlates nothing and
# `run watch` times out into status:no-workflow even when CI ran and passed.
# The fix resolves the branch head SHA up front and falls back to head_sha
# correlation when the branch-filtered lookup is empty.
#
# The tests exercise the pre-check fallback (terminal-state-before-sleep) so no
# real waiting is needed. Uses mock git/tea via PATH injection.
#
# Usage: bash tests/git-cli/test-run-watch-gitea.sh [filter]

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

# The branch head SHA the watcher resolves via `git rev-parse`, and the SHA the
# (empty-branch) Gitea run reports as head_sha. They share a 12-char prefix.
BRANCH_SHA="abcdef1234567890abcdef1234567890abcdef12"
RUN_SHA="abcdef1234567890ffffffffffffffffffffffff" # same first 12 chars

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
# Mock builders
# ---------------------------------------------------------------------------

# Mock git: Gitea remote + a configurable rev-parse SHA for the branch.
write_git_mock() {
  local sha="$1"
  cat >"$MOCK_DIR/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "remote get-url origin") echo "https://git.stonefish.tech/owner/repo.git" ;;
  "rev-parse feature-widget"|"rev-parse origin/feature-widget") echo "$sha" ;;
  *) PATH=\${PATH#"\${0%/*}":}; exec git "\$@" ;;
esac
EOF
  chmod +x "$MOCK_DIR/git"
}

# Mock tea:
#  - login list                → gitea platform detection
#  - api .../actions/runs?...   → one run with EMPTY head_branch but a populated
#                                 head_sha ($RUN_SHA), conclusion success
#  - api .../actions/runs/<id>  → run detail (success)
#  - api .../actions/runs/<id>/jobs → all jobs success (so _run_failed_jobs empty)
write_tea_mock() {
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "\$1" in
  api)
    case "\$2" in
      repos/\\{owner\\}/\\{repo\\}/actions/runs/*/jobs)
        echo '{"jobs":[{"id":1,"name":"build","status":"completed","conclusion":"success"}]}'
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs/*)
        cat <<'JSON'
{
  "id": 1075, "status": "completed", "conclusion": "success",
  "name": "CI", "head_branch": "", "head_sha": "$RUN_SHA",
  "event": "pull_request", "run_started_at": "2026-06-01T12:00:00Z",
  "url": "https://git.stonefish.tech/owner/repo/actions/runs/1075"
}
JSON
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs*)
        cat <<'JSON'
{"workflow_runs":[
  {
    "id": 1075, "status": "completed", "conclusion": "success",
    "name": "CI", "head_branch": "", "branch": "", "head_sha": "$RUN_SHA",
    "event": "pull_request", "run_started_at": "2026-06-01T12:00:00Z",
    "url": "https://git.stonefish.tech/owner/repo/actions/runs/1075"
  }
]}
JSON
        ;;
      *) echo "unexpected tea api call: \$2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected tea call: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"
}

# ---------------------------------------------------------------------------
# Test: empty-branch run is correlated by head_sha → status: pass
# ---------------------------------------------------------------------------

echo "── run watch: Gitea head-SHA fallback (#140) ──"

label="run watch correlates empty-branch run via head_sha → pass"
if ! skip_filter "$label"; then
  write_git_mock "$BRANCH_SHA"
  write_tea_mock

  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch --branch feature-widget \
    --initial-delay 0 --interval 0 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")

  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$stderr"
  fi
fi

# ---------------------------------------------------------------------------
# Test: SHA mismatch → fallback finds nothing → no-workflow (scoped, not blanket)
# ---------------------------------------------------------------------------

label="run watch: SHA mismatch does not blanket-match → no-workflow"
if ! skip_filter "$label"; then
  write_git_mock "0000000000000000000000000000000000000000" # different prefix
  write_tea_mock

  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_CLI" run watch --branch feature-widget \
    --initial-delay 0 --interval 0 2>"$MOCK_DIR/stderr") || exit_code=$?
  stderr=$(cat "$MOCK_DIR/stderr")

  if [[ "$exit_code" == "3" ]] && echo "$output" | grep -q "^status: no-workflow"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$stderr"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
