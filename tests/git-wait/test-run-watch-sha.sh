#!/usr/bin/env bash
# test-run-watch-sha.sh — Test harness for git-wait `run watch --sha`.
#
# Regression test for the newest-run-only blind spot in `run watch --branch`:
# it follows a single run, so when a commit (or a branch) has more than one run
# in flight, the newest reporting success ends the watch while another is still
# executing. Observed live on a default branch after two PRs merged in quick
# succession -- the watcher printed "status: pass" for the second merge's run
# and never looked at the first, which was still in progress.
#
# `--sha` is the fix: it watches EVERY run for one commit, stays pending while
# any of them is pending, and fails if any run -- or any job inside one --
# failed.
#
# Uses mock git/tea via PATH injection; the Gitea path is mocked because the
# aggregation operates on _run_list's normalized output and is platform-
# independent.
#
# Usage: bash tests/git-wait/test-run-watch-sha.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_WAIT="$SCRIPT_DIR/../../utils/git-wait"
source "$SCRIPT_DIR/../lib/mock-git.sh"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

MOCK_DIR=""
cleanup() { [[ -n "$MOCK_DIR" ]] && rm -rf "$MOCK_DIR"; }
trap cleanup EXIT
MOCK_DIR=$(mktemp -d)

# A full 40-char SHA, so the watcher's normalization passes it straight through
# without needing git rev-parse to resolve anything.
SHA="abcdef1234567890abcdef1234567890abcdef12"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"

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

write_git_mock() {
  write_mock_git "$MOCK_DIR" "https://git.stonefish.tech/owner/repo.git"
}

# Mock tea with TWO runs sharing one head_sha, each independently configurable.
#   $1/$2 run 1075 status/conclusion   $3 run 1075 job conclusion
#   $4/$5 run 1076 status/conclusion   $6 run 1076 job conclusion
#   $7 list order: "oldest-first" (default) or "newest-first"
#
# Order matters for the --branch comparison below: --branch takes .[0] of the
# run list, so which run appears first decides what it sees.
write_tea_mock() {
  local s1="$1" c1="$2" j1="$3" s2="$4" c2="$5" j2="$6" order="${7:-oldest-first}"
  local r1 r2 runs
  r1='{"id":1075,"status":"'"$s1"'","conclusion":"'"$c1"'","name":"CI","head_branch":"main","branch":"main","head_sha":"'"$SHA"'","event":"push","run_started_at":"2026-06-01T12:00:00Z","url":"https://git.stonefish.tech/owner/repo/actions/runs/1075"}'
  r2='{"id":1076,"status":"'"$s2"'","conclusion":"'"$c2"'","name":"Release","head_branch":"main","branch":"main","head_sha":"'"$SHA"'","event":"push","run_started_at":"2026-06-01T12:01:00Z","url":"https://git.stonefish.tech/owner/repo/actions/runs/1076"}'
  if [[ "$order" == "newest-first" ]]; then runs="$r2,$r1"; else runs="$r1,$r2"; fi
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
case "\$1 \$2 \$3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
esac
case "\$1" in
  api)
    case "\$2" in
      repos/\\{owner\\}/\\{repo\\}/actions/runs/1075/jobs)
        echo '{"jobs":[{"id":1,"name":"build","status":"completed","conclusion":"$j1"}]}'
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs/1076/jobs)
        echo '{"jobs":[{"id":2,"name":"release","status":"completed","conclusion":"$j2"}]}'
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs/1075)
        echo '{"id":1075,"status":"$s1","conclusion":"$c1","name":"CI","head_branch":"main","head_sha":"$SHA","event":"push","run_started_at":"2026-06-01T12:00:00Z","url":"https://git.stonefish.tech/owner/repo/actions/runs/1075"}'
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs/1076)
        echo '{"id":1076,"status":"$s2","conclusion":"$c2","name":"Release","head_branch":"main","head_sha":"$SHA","event":"push","run_started_at":"2026-06-01T12:01:00Z","url":"https://git.stonefish.tech/owner/repo/actions/runs/1076"}'
        ;;
      repos/\\{owner\\}/\\{repo\\}/actions/runs*)
        echo '{"workflow_runs":[$runs]}'
        ;;
      *) echo "unexpected tea api call: \$2" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected tea call: \$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"
}

run_watch() {
  PATH="$MOCK_DIR:$PATH" bash "$GIT_WAIT" run watch "$@" 2>"$MOCK_DIR/stderr"
}

# ---------------------------------------------------------------------------
echo "── run watch --sha: usage guards ──"

# These assert on argument parsing, but git-wait resolves PLATFORM before it
# ever reaches the dispatcher -- so tea must be mocked here too. Without it the
# mock git's Gitea remote sends detection to the REAL tea on PATH, which fails
# on a machine with no tea login and succeeds on one that happens to have a
# login for this host. That made these three pass locally and fail in CI.
label="neither --branch nor --sha → usage error"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch) || exit_code=$?
  if [[ "$exit_code" == "1" ]] && grep -q "requires --branch or --sha" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--branch and --sha together → usage error"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --branch main --sha "$SHA") || exit_code=$?
  if [[ "$exit_code" == "1" ]] && grep -q "not both" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# A short SHA silently matches nothing on `gh run list --commit`, so it must be
# rejected rather than reported as no-workflow.
label="unresolvable short --sha → usage error, not no-workflow"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --sha deadbee --initial-delay 0) || exit_code=$?
  if [[ "$exit_code" == "1" ]] && grep -q "full 40-character SHA" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# ---------------------------------------------------------------------------
echo "── run watch --sha: aggregation across every run for the commit ──"

label="all runs terminal and green → pass, both runs counted"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass" &&
    grep -q "2 run(s), 0 pending" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# The core regression: newest run green, older still running. --branch would
# have reported pass here; --sha must keep waiting and then time out.
label="one run still in progress → does NOT report pass (times out)"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock in_progress "" success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --timeout 2 --idle-timeout 0) || exit_code=$?
  if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "^status: timeout" &&
    ! echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# The failure this bug would hide: the newest run passes, an older one failed.
label="newest run green but another failed → fail"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed failure failure completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: fail" &&
    echo "$output" | grep -q "run-1075:failure"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# #87 applies per run: a run-level success can still hide a failed job.
label="run-level success hiding a failed job → fail (#87, per run)"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success failure
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: fail" &&
    echo "$output" | grep -q "release"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="cancelled run is terminal and fails, not silently passed"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed cancelled success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: fail" &&
    echo "$output" | grep -q "cancelled"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="no run for the commit → no-workflow, scoped to that SHA"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --sha "$OTHER_SHA" --initial-delay 0 --interval 1 --timeout 0 --idle-timeout 0 --no-run-timeout 2) || exit_code=$?
  if [[ "$exit_code" == "3" ]] && echo "$output" | grep -q "^status: no-workflow"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# ---------------------------------------------------------------------------
# The bug, pinned: identical data, the two flags disagree. The green run is
# listed first (as GitHub returns newest-first), so --branch sees only it while
# an older run is still in progress. This is the exact shape that reported a
# passing post-merge watch on a default branch while another run was mid-flight.
#
# The --branch assertion documents CURRENT, DELIBERATE behaviour, not an
# endorsement: --branch follows one run. If that is ever changed, this test
# should fail and force the change to be a considered one.
# ---------------------------------------------------------------------------
echo "── --branch vs --sha on identical data (the pinned limitation) ──"

label="--branch sees only the newest run → reports pass while another is pending"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock in_progress "" success completed success success newest-first
  exit_code=0
  output=$(run_watch --branch main --initial-delay 0 --interval 1 --timeout 2 --idle-timeout 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--sha on the SAME data refuses to pass while a run is pending"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock in_progress "" success completed success success newest-first
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --timeout 2 --idle-timeout 0) || exit_code=$?
  if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "^status: timeout" &&
    ! echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# ---------------------------------------------------------------------------
echo "── patience: heartbeat alerts, no-run window, defaults ──"

label="pending run → heartbeat alert on stderr only, stdout unchanged"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock in_progress "" success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --timeout 3 --alert-interval 1) || exit_code=$?
  if [[ "$exit_code" == "2" ]] && grep -q "still running after .*1 run(s) pending: CI" "$MOCK_DIR/stderr" &&
    ! echo "$output" | grep -q "still running"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--alert-interval 0 disables heartbeat alerts"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock in_progress "" success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --timeout 2 --alert-interval 0) || exit_code=$?
  if [[ "$exit_code" == "2" ]] && ! grep -q "still running" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--no-run-timeout: keeps waiting with stderr alerts, then no-workflow"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --sha "$OTHER_SHA" --initial-delay 0 --interval 1 --no-run-timeout 3) || exit_code=$?
  waits=$(grep -c "no runs yet for .*, still waiting (.*s of 3s)" "$MOCK_DIR/stderr" || true)
  if [[ "$exit_code" == "3" ]] && echo "$output" | grep -q "^status: no-workflow" &&
    [[ "$waits" -ge 2 ]] && ! echo "$output" | grep -q "still waiting"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code waits=$waits output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="a run appearing inside the no-run window is picked up (no premature no-workflow)"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  # Serve an empty list for the first two polls, then the real runs.
  mv "$MOCK_DIR/tea" "$MOCK_DIR/tea.real"
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" && "\$2" == repos/*/actions/runs?* ]]; then
  n=\$(cat "$MOCK_DIR/polls" 2>/dev/null || echo 0)
  echo \$((n + 1)) >"$MOCK_DIR/polls"
  if [[ "\$n" -lt 2 ]]; then echo '{"workflow_runs":[]}'; exit 0; fi
fi
exec "$MOCK_DIR/tea.real" "\$@"
EOF
  chmod +x "$MOCK_DIR/tea"
  rm -f "$MOCK_DIR/polls"
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --no-run-timeout 10) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="defaults: idle-timeout disabled, 4h ceiling, alert/no-run flags documented"
if ! skip_filter "$label"; then
  help=$(bash "$GIT_WAIT" --help 2>&1 || true)
  if echo "$help" | grep -q -- "--idle-timeout 0" && echo "$help" | grep -q -- "--timeout 14400" &&
    echo "$help" | grep -q -- "--alert-interval 300" && echo "$help" | grep -q -- "--no-run-timeout 600"; then
    pass "$label"
  else
    fail "$label" "help text missing new defaults"
  fi
fi

# ---------------------------------------------------------------------------
echo "── run watch --sha: failed polls and settle window ──"

# Wrap the base tea mock: for the first $1 runs-list polls act per $2:
#   fail -> exit 1 (API error)    one -> serve only the first run
wrap_list_polls() {
  local n="$1" mode="$2"
  mv "$MOCK_DIR/tea" "$MOCK_DIR/tea.real"
  cat >"$MOCK_DIR/tea" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" && "\$2" == repos/*/actions/runs?* ]]; then
  c=\$(cat "$MOCK_DIR/polls" 2>/dev/null || echo 0)
  echo \$((c + 1)) >"$MOCK_DIR/polls"
  if [[ "\$c" -lt $n ]]; then
    if [[ "$mode" == "fail" ]]; then echo "boom" >&2; exit 1; fi
    "$MOCK_DIR/tea.real" "\$@" | jq -c '.workflow_runs |= .[0:1]'; exit 0
  fi
fi
exec "$MOCK_DIR/tea.real" "\$@"
EOF
  chmod +x "$MOCK_DIR/tea"
  rm -f "$MOCK_DIR/polls"
}

label="failed list calls are not 'no runs': retried, then pass despite tiny --no-run-timeout"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 3 fail
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --no-run-timeout 1) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass" &&
    grep -q "run list failed" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="persistently failing list -> status: error, exit 4 after --max-poll-failures, never no-workflow"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 1000 fail
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --no-run-timeout 1 --max-poll-failures 3 --timeout 60) || exit_code=$?
  if [[ "$exit_code" == "4" ]] && echo "$output" | grep -q "^status: error" &&
    ! echo "$output" | grep -q "no-workflow" && [[ "$(cat "$MOCK_DIR/polls")" == "3" ]]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="failures below --max-poll-failures recover (counter resets on success)"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 2 fail
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --settle 0 --max-poll-failures 3) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--max-poll-failures 0 disables the cap: persistent failure ends in timeout"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 1000 fail
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --no-run-timeout 1 --max-poll-failures 0 --timeout 3) || exit_code=$?
  if [[ "$exit_code" == "2" ]] && echo "$output" | grep -q "^status: timeout"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--settle: chained run appearing during the window is watched, then pass with 2 runs"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 2 one
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --settle 5) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass" &&
    grep -q "settling" "$MOCK_DIR/stderr" && grep -q "new run appeared" "$MOCK_DIR/stderr" &&
    grep -q "^runs: 2" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--settle: chained run that fails after settling started -> fail"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed failure failure
  wrap_list_polls 2 one
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --settle 5) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: fail"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--settle N with no chained run: settles then passes"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  wrap_list_polls 1000 one
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --settle 2) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass" &&
    grep -q "settling" "$MOCK_DIR/stderr"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

label="--settle 0 disables settling; help documents --settle 30"
if ! skip_filter "$label"; then
  write_git_mock
  write_tea_mock completed success success completed success success
  exit_code=0
  output=$(run_watch --sha "$SHA" --initial-delay 0 --interval 1 --settle 0) || exit_code=$?
  if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "^status: pass" &&
    ! grep -q "settling" "$MOCK_DIR/stderr" &&
    bash "$GIT_WAIT" --help 2>&1 | grep -q -- "--settle 30"; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code output=$output stderr=$(cat "$MOCK_DIR/stderr")"
  fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]]
