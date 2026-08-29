#!/usr/bin/env bash
# check-ci-parity.sh — assert validate-all.sh runs everything CI runs.
#
# validate-all.sh is documented as the single local equivalent of CI. That claim
# is only true if the two lists agree, and a comment asking humans to keep them
# in step is exactly the kind of thing that silently rots — CLAUDE.md claimed
# "four checks" while CI ran five, and the missing one had no local equivalent
# at all. This turns that convention into a check.
#
# Compares the check commands in .github/workflows/ci.yml against the
# run_check lines in validate-all.sh. Setup steps (installing jq, rumdl) are
# not checks and are ignored.
#
# Usage: bash .github/scripts/check-ci-parity.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

WORKFLOW=".github/workflows/ci.yml"
VALIDATE_ALL=".github/scripts/validate-all.sh"

for f in "$WORKFLOW" "$VALIDATE_ALL"; do
  [[ -f "$f" ]] || {
    echo "missing $f" >&2
    exit 1
  }
done

# Check commands are single-line `run:` steps invoking a script or linter.
# Anything else (multi-line `run: |` install blocks) is setup, not a check.
mapfile -t ci_cmds < <(
  grep -oE '^\s+run: (bash [^ ]+\.sh|rumdl check \.)$' "$WORKFLOW" |
    sed -E 's/^\s+run: //' | sort -u
)

if [[ ${#ci_cmds[@]} -eq 0 ]]; then
  echo "no check commands found in $WORKFLOW — parsing likely broke" >&2
  exit 1
fi

missing=0
for cmd in "${ci_cmds[@]}"; do
  if grep -qF -- "$cmd" "$VALIDATE_ALL"; then
    printf '  ok      %s\n' "$cmd"
  else
    printf '  MISSING %s\n' "$cmd"
    missing=1
  fi
done

echo ""
if [[ $missing -eq 0 ]]; then
  echo "CI parity: validate-all.sh covers all ${#ci_cmds[@]} CI check(s)."
else
  echo "CI parity FAILED — $VALIDATE_ALL does not run every CI check." >&2
  echo "Add the missing command(s) to $VALIDATE_ALL so a local run matches CI." >&2
  exit 1
fi
