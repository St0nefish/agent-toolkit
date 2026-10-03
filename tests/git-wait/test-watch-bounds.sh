#!/usr/bin/env bash
# test-watch-bounds.sh — git-wait waits must stay bounded when nothing happens.
#
# Covers: the --timeout ceiling on the no-run path, and the
# `run watch --branch` PR path (failed `gh pr view`, no checks registered).
# Tiny intervals; mock git/gh/tea via PATH injection.
#
# Usage: bash tests/git-wait/test-watch-bounds.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_WAIT="$SCRIPT_DIR/../../utils/git-wait"
source "$SCRIPT_DIR/../lib/mock-git.sh"

PASS=0
FAIL=0
FILTER="${1:-}"

MOCK_DIR=""
cleanup() { [[ -n "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"; }
trap cleanup EXIT
MOCK_DIR=$(mktemp -d)

SHA="abcdef1234567890abcdef1234567890abcdef12"

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
skip_filter() { [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; }

# Run git-wait; sets OUT, CODE, DUR.
gw() {
  local start=$SECONDS
  CODE=0
  OUT=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_WAIT" "$@" 2>"$MOCK_DIR/stderr") || CODE=$?
  DUR=$((SECONDS - start))
}

echo "── --timeout ceiling on no-run paths ──"

write_empty_tea() {
  write_mock_git "$MOCK_DIR" "https://git.stonefish.tech/owner/repo.git"
  cat >"$MOCK_DIR/tea" <<'EOS'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "$1" in
  api) echo '{"workflow_runs":[]}' ;;
  *) echo '[]' ;;
esac
EOS
  chmod +x "$MOCK_DIR/tea"
}

label="--sha: no runs + --timeout 1 reports timeout, not a full --no-run-timeout"
if ! skip_filter "$label"; then
  write_empty_tea
  gw run watch --sha "$SHA" --initial-delay 0 --interval 1 --timeout 1 --no-run-timeout 60
  if [[ "$CODE" == "2" && "$OUT" == *"status: timeout"* && "$DUR" -lt 20 ]]; then
    pass "$label"
  else
    fail "$label" "exit=$CODE dur=${DUR}s out=$OUT"
  fi
fi

label="--branch: no runs + --timeout 1 reports timeout"
if ! skip_filter "$label"; then
  write_empty_tea
  gw run watch --branch feat --initial-delay 0 --interval 1 --timeout 1 --no-run-timeout 60
  if [[ "$CODE" == "2" && "$OUT" == *"status: timeout"* && "$DUR" -lt 20 ]]; then
    pass "$label"
  else
    fail "$label" "exit=$CODE dur=${DUR}s out=$OUT"
  fi
fi

echo "── run watch --branch on the GitHub PR path ──"

# gh mock: `pr view <branch> --json number,url` finds PR 7; the polling call
# (state,statusCheckRollup,url) behaves per mode: fail | empty.
write_gh_mock() {
  local mode="$1"
  write_mock_git "$MOCK_DIR" "https://github.com/test/repo.git"
  cat >"$MOCK_DIR/gh" <<EOS
#!/usr/bin/env bash
case "\$*" in
  *"--json number,url"*) echo '{"number":7,"url":"https://github.com/test/repo/pull/7"}' ;;
  *"state,statusCheckRollup"*)
    if [[ "$mode" == "fail" ]]; then echo "api down" >&2; exit 1; fi
    echo '{"state":"OPEN","statusCheckRollup":[],"url":"https://github.com/test/repo/pull/7"}'
    ;;
  *) exit 1 ;;
esac
EOS
  chmod +x "$MOCK_DIR/gh"
}

label="failed gh pr view counts as failed poll -> status: error, exit 4"
if ! skip_filter "$label"; then
  write_gh_mock fail
  gw run watch --branch feat --initial-delay 0 --interval 1 --timeout 60 --max-poll-failures 2
  if [[ "$CODE" == "4" && "$OUT" == *"status: error"* && "$DUR" -lt 20 ]]; then
    pass "$label"
  else
    fail "$label" "exit=$CODE dur=${DUR}s out=$OUT"
  fi
fi

label="PR with no checks registered -> no-workflow after --no-run-timeout"
if ! skip_filter "$label"; then
  write_gh_mock empty
  gw run watch --branch feat --initial-delay 0 --interval 1 --timeout 60 --no-run-timeout 2
  if [[ "$CODE" == "3" && "$OUT" == *"status: no-workflow"* && "$DUR" -lt 20 ]]; then
    pass "$label"
  else
    fail "$label" "exit=$CODE dur=${DUR}s out=$OUT"
  fi
fi

echo "── flag contracts ──"

label="--settle with --branch is a usage error (exit 1)"
if ! skip_filter "$label"; then
  write_empty_tea
  gw run watch --branch feat --settle 30
  if [[ "$CODE" == "1" && "$(cat "$MOCK_DIR/stderr")" == *"--settle requires --sha"* ]]; then
    pass "$label"
  else
    fail "$label" "exit=$CODE out=$OUT"
  fi
fi

label="help documents the 900s --branch no-run default"
if ! skip_filter "$label"; then
  if bash "$GIT_WAIT" --help 2>&1 | grep -q -- "--no-run-timeout 600|900"; then
    pass "$label"
  else
    fail "$label" "help text missing 600|900"
  fi
fi

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
