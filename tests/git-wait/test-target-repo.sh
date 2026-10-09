#!/usr/bin/env bash
# test-target-repo.sh — git-wait -C DIR retargets every call at another repo.
#
# Two real throwaway repos (GitHub-hosted and Gitea-hosted origins) plus a tea
# login stub on PATH. git-wait is always launched from a third, unrelated
# directory so a pass proves -C — not the working directory — chose the repo.
#
# Usage: bash tests/git-wait/test-target-repo.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_WAIT="$SCRIPT_DIR/../../utils/git-wait"

PASS=0
FAIL=0
FILTER="${1:-}"

WORK=""
cleanup() { [[ -n "$WORK" ]] && rm -rf "$WORK"; }
trap cleanup EXIT
WORK=$(mktemp -d)

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}
fail() {
  printf "  \033[31m✗\033[0m %s  (%s)\n" "$1" "$2"
  ((FAIL++)) || true
}
skip_filter() { [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"; }

mkdir -p "$WORK/bin" "$WORK/github-repo" "$WORK/gitea-repo" "$WORK/elsewhere" "$WORK/not-a-repo"
git init -q "$WORK/github-repo"
git -C "$WORK/github-repo" remote add origin "https://github.com/owner/repo.git"
git init -q "$WORK/gitea-repo"
git -C "$WORK/gitea-repo" remote add origin "https://git.example.test/owner/repo.git"

# Only the Gitea host is a configured tea login; anything else falls to gh.
cat >"$WORK/bin/tea" <<'EOS'
#!/usr/bin/env bash
case "$1 $2 $3" in
  "login list --output") echo '[{"url":"https://git.example.test"}]' ;;
  *) exit 1 ;;
esac
EOS
chmod +x "$WORK/bin/tea"
# Platform detection never calls gh, but the script requires it on PATH.
printf '#!/usr/bin/env bash\nexit 1\n' >"$WORK/bin/gh"
chmod +x "$WORK/bin/gh"

# Run git-wait from an unrelated cwd; sets OUT, ERR, CODE.
gw() {
  CODE=0
  OUT=$(cd "$WORK/elsewhere" && PATH="$WORK/bin:$PATH" bash "$GIT_WAIT" "$@" 2>"$WORK/stderr") || CODE=$?
  ERR=$(cat "$WORK/stderr")
}

echo "── -C DIR ──"

label="-C picks the GitHub repo regardless of cwd"
if ! skip_filter "$label"; then
  gw -C "$WORK/github-repo" platform
  if [[ "$CODE" == "0" && "$OUT" == "github" ]]; then pass "$label"; else fail "$label" "exit=$CODE out=$OUT err=$ERR"; fi
fi

label="-C picks the Gitea repo regardless of cwd"
if ! skip_filter "$label"; then
  gw -C "$WORK/gitea-repo" platform
  if [[ "$CODE" == "0" && "$OUT" == "gitea" ]]; then pass "$label"; else fail "$label" "exit=$CODE out=$OUT err=$ERR"; fi
fi

label="--repo-dir is an alias for -C"
if ! skip_filter "$label"; then
  gw --repo-dir "$WORK/gitea-repo" platform
  if [[ "$CODE" == "0" && "$OUT" == "gitea" ]]; then pass "$label"; else fail "$label" "exit=$CODE out=$OUT err=$ERR"; fi
fi

label="-C composes with a subcommand (run watch usage error comes from the target)"
if ! skip_filter "$label"; then
  gw -C "$WORK/github-repo" run watch --branch feat --settle 30
  if [[ "$CODE" == "1" && "$ERR" == *"--settle requires --sha"* ]]; then pass "$label"; else fail "$label" "exit=$CODE err=$ERR"; fi
fi

echo "── -C validation ──"

label="nonexistent directory is a usage error (exit 1)"
if ! skip_filter "$label"; then
  gw -C "$WORK/missing" platform
  if [[ "$CODE" == "1" && "$ERR" == *"not a directory"* ]]; then pass "$label"; else fail "$label" "exit=$CODE err=$ERR"; fi
fi

label="non-git directory is a usage error (exit 1)"
if ! skip_filter "$label"; then
  gw -C "$WORK/not-a-repo" platform
  if [[ "$CODE" == "1" && "$ERR" == *"not a git repository"* ]]; then pass "$label"; else fail "$label" "exit=$CODE err=$ERR"; fi
fi

label="-C without a value is a usage error (exit 1)"
if ! skip_filter "$label"; then
  gw -C
  if [[ "$CODE" == "1" && "$ERR" == *"requires a directory"* ]]; then pass "$label"; else fail "$label" "exit=$CODE err=$ERR"; fi
fi

echo ""
echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]]
