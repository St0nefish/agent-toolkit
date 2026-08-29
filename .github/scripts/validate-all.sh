#!/usr/bin/env bash
# validate-all.sh — run every check CI runs, in one command.
#
# This is the single source of truth for "what CI will check". CLAUDE.md points
# here rather than listing the commands, so the docs cannot drift out of sync
# with the workflow the way `rumdl .` did (it was never a valid invocation, so
# the documented markdown lint silently never ran).
#
# Each check is also a CI job in .github/workflows/ci.yml, which runs them in
# parallel for per-job status. Keep the two lists in step: if you add a job
# there, add it here.
#
# Usage: bash .github/scripts/validate-all.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

declare -a names=() results=()
failed=0

run_check() {
  local name="$1"
  shift
  echo "==============================="
  echo "=== $name"
  echo "==============================="
  names+=("$name")
  if "$@"; then
    results+=("PASS")
  else
    results+=("FAIL")
    failed=1
  fi
  echo ""
}

run_check "ci parity" bash .github/scripts/check-ci-parity.sh
run_check "plugin tests" bash test.sh
run_check "plugin structure" bash .github/scripts/validate-plugins.sh
run_check "frontmatter" bash .github/scripts/validate-frontmatter.sh
run_check "markdown lint" rumdl check .
run_check "shell lint" bash .github/scripts/lint-shell.sh

echo "==============================="
echo "=== Summary"
echo "==============================="
for i in "${!names[@]}"; do
  printf "  %-20s [%s]\n" "${names[$i]}" "${results[$i]}"
done
echo ""

if [[ $failed -eq 0 ]]; then
  echo "All checks passed."
else
  echo "Some checks failed."
fi

exit "$failed"
