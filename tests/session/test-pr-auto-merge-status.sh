#!/usr/bin/env bash
# test-pr-auto-merge-status.sh — Test harness for git-wait's auto-merge
# progress signal inside `pr wait`.
#
# `pr auto-merge-status` is no longer a public subcommand — it survives only
# as the private `_auto_merge_status` function, called from `pr wait`'s poll
# loop (GitHub only) to decide whether a pending auto-merge counts as
# progress. A pending auto-merge must reset the idle clock just like pending
# CI does (issue #149's progress-aware timeout), so a PR queued for
# auto-merge is never abandoned to the idle timeout while GitHub is still
# working on it — it can only be given up on via the absolute ceiling.
#
# These tests mock `gh pr view --json autoMergeRequest` (via a single
# response object shared across all `pr:view` calls, since `pr wait` queries
# several different --json projections of the same PR) and assert on the
# resulting `pr wait` behaviour rather than a raw `auto_merge:` line.
#
# Uses mock gh/tea scripts via PATH manipulation.
#
# Usage: bash tests/session/test-pr-auto-merge-status.sh [filter]

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

write_mock_gh() {
  cat >"$MOCK_DIR/gh" <<'MOCK_HEADER'
#!/usr/bin/env bash
# Mock gh script for pr wait / auto-merge-signal tests
MOCK_HEADER
  cat >>"$MOCK_DIR/gh"
  chmod +x "$MOCK_DIR/gh"
}

# Mock git so platform detection works (returns github.com remote)
write_mock_git "$MOCK_DIR" "https://github.com/test/repo.git"

skip_filter() {
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

# ---------------------------------------------------------------------------
# Test: a pending auto-merge counts as progress, so pr wait must not give up
# via the idle timeout — with a tiny idle window but a larger ceiling, it
# must run out the ceiling instead (reason: "max wait", not "no progress").
# This mirrors the existing "pending CI defeats idle" case in
# test-pr-wait.sh, but for the auto-merge signal instead of statusCheckRollup.
# ---------------------------------------------------------------------------

echo "── pr wait: auto-merge pending counts as progress ──"

label="auto-merge pending → idle never fires, wait runs to the ceiling"
if ! skip_filter "$label"; then
  write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":30,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/30"}]'
    ;;
  pr:view)
    echo '{"number":30,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/30","comments":[],"statusCheckRollup":[],"autoMergeRequest":{"enabledAt":"2024-01-01T00:00:00Z","enabledBy":{"login":"u"},"mergeMethod":"MERGE"}}'
    ;;
esac
EOF

  start=$SECONDS
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_WAIT" pr wait \
    --branch "test-branch" --idle-timeout 1 --timeout 4 --interval 1 2>"$MOCK_DIR/stderr") || exit_code=$?
  duration=$((SECONDS - start))
  stderr=$(cat "$MOCK_DIR/stderr")
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
  got_reason=$(echo "$output" | grep '^reason:' | head -1 | sed 's/^reason: *//')

  errs=()
  [[ "$got_status" == "timeout" ]] || errs+=("status='$got_status' (expected timeout)")
  [[ "$exit_code" == "2" ]] || errs+=("exit=$exit_code (expected 2)")
  [[ "$got_reason" == *"max wait"* ]] || errs+=("reason='$got_reason' (expected 'max wait', not an idle timeout)")
  [[ "$duration" -ge 3 ]] || errs+=("duration=${duration}s (expected to run to the ~4s ceiling, not the 1s idle window)")
  echo "$stderr" | grep -q "auto_merge=true" || errs+=("stderr never showed auto_merge=true — signal not observed")

  if [[ ${#errs[@]} -eq 0 ]]; then
    printf "  \033[32m✓\033[0m %s (reason='%s', %ss)\n" "$label" "$got_reason" "$duration"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (%s)\n" "$label" "$(
      IFS='; '
      echo "${errs[*]}"
    )"
    ((FAIL++)) || true
  fi
fi

# ---------------------------------------------------------------------------
# Test: no auto-merge and no CI signal → idle timeout fires as normal (sanity
# check that the auto-merge mock isn't accidentally always "progressing").
# ---------------------------------------------------------------------------

label="no auto-merge, no CI → idle timeout fires (baseline, no false progress)"
if ! skip_filter "$label"; then
  write_mock_gh <<'EOF'
case "$1:$2" in
  pr:list)
    echo '[{"number":31,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/31"}]'
    ;;
  pr:view)
    echo '{"number":31,"title":"Test PR","body":"","state":"OPEN","author":{"login":"u"},"headRefName":"test-branch","baseRefName":"main","labels":[],"assignees":[],"mergeable":"MERGEABLE","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","url":"https://github.com/test/repo/pull/31","comments":[],"statusCheckRollup":[],"autoMergeRequest":null}'
    ;;
esac
EOF

  start=$SECONDS
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_WAIT" pr wait \
    --branch "test-branch" --idle-timeout 2 --timeout 100 --interval 1 2>"$MOCK_DIR/stderr") || exit_code=$?
  duration=$((SECONDS - start))
  stderr=$(cat "$MOCK_DIR/stderr")
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
  got_reason=$(echo "$output" | grep '^reason:' | head -1 | sed 's/^reason: *//')

  if [[ "$got_status" == "timeout" && "$exit_code" == "2" && "$got_reason" == *"no progress"* && "$duration" -lt 20 ]]; then
    printf "  \033[32m✓\033[0m %s (reason='%s', %ss)\n" "$label" "$got_reason" "$duration"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (status=%s exit=%s reason='%s' dur=%ss stderr=%s)\n" \
      "$label" "$got_status" "$exit_code" "$got_reason" "$duration" "$stderr"
    ((FAIL++)) || true
  fi
fi

# ---------------------------------------------------------------------------
# Test: Gitea has no auto-merge detection — `_auto_merge_status` is never
# consulted on that path (pr wait hardcodes auto_merge="false" for
# PLATFORM!=github), so a Gitea PR with no CI signal must hit the idle
# timeout exactly like GitHub with no auto-merge, never treating the
# platform gap as false progress.
# ---------------------------------------------------------------------------

label="[gitea] no auto-merge signal on this platform → idle timeout fires normally"
if ! skip_filter "$label"; then
  write_mock_git "$MOCK_DIR" "https://git.stonefish.tech/owner/repo.git"
  cat >"$MOCK_DIR/tea" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "login list --output") echo '[{"url":"https://git.stonefish.tech"}]'; exit 0 ;;
  "pr list --output")
    echo '[{"index":32,"title":"Test PR","body":"","state":"open","head":"test-branch","base":"main","author":"u","labels":[],"assignees":[],"mergeable":null,"created":"2024-01-01T00:00:00Z","updated":"2024-01-01T00:00:00Z","url":"https://git.stonefish.tech/owner/repo/pulls/32"}]'
    exit 0
    ;;
esac
case "$1:$2" in
  api:repos/{owner}/{repo}/pulls/32)
    echo '{"number":32,"title":"Test PR","body":"","state":"open","merged":false,"merged_at":null,"mergeable":true,"user":{"login":"u"},"head":{"ref":"test-branch"},"base":{"ref":"main"},"labels":[],"assignees":[],"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","html_url":"https://git.stonefish.tech/owner/repo/pulls/32"}'
    ;;
  *) echo "unexpected tea call: $*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$MOCK_DIR/tea"

  start=$SECONDS
  exit_code=0
  output=$(PATH="$MOCK_DIR:$PATH" bash "$GIT_WAIT" pr wait \
    --branch "test-branch" --idle-timeout 2 --timeout 100 --interval 1 2>"$MOCK_DIR/stderr") || exit_code=$?
  duration=$((SECONDS - start))
  got_status=$(echo "$output" | grep '^status:' | head -1 | sed 's/^status: *//')
  got_reason=$(echo "$output" | grep '^reason:' | head -1 | sed 's/^reason: *//')

  # Restore the GitHub git mock for any suites that might run after this file.
  write_mock_git "$MOCK_DIR" "https://github.com/test/repo.git"
  rm -f "$MOCK_DIR/tea"

  if [[ "$got_status" == "timeout" && "$exit_code" == "2" && "$got_reason" == *"no progress"* && "$duration" -lt 20 ]]; then
    printf "  \033[32m✓\033[0m %s (reason='%s', %ss)\n" "$label" "$got_reason" "$duration"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (status=%s exit=%s reason='%s' dur=%ss)\n" \
      "$label" "$got_status" "$exit_code" "$got_reason" "$duration"
    ((FAIL++)) || true
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
