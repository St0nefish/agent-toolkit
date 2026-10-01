#!/usr/bin/env bash
# check-rumdl-version.sh — warn when the local rumdl differs from the one CI pins.
#
# CI installs one specific rumdl release (see the "Install rumdl" step in
# .github/workflows/ci.yml), but validate-all.sh runs whatever `rumdl` is first
# on PATH. Rule behavior changes between releases — a code span with a leading
# space (MD038) passed locally on 0.2.69 and failed CI on 0.1.53 — so a green
# local run is only meaningful when the versions match.
#
# This only warns (exit 0): developers legitimately run newer versions, and a
# hard failure would block unrelated work. It exists so the mismatch is visible
# instead of discovered after a push.
#
# Usage: bash .github/scripts/check-rumdl-version.sh [workflow-file]
# Exit:  0 versions match, or mismatch warned about
#        1 the pinned version could not be determined (parsing likely broke)

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

WORKFLOW="${1:-.github/workflows/ci.yml}"

[[ -f "$WORKFLOW" ]] || {
  echo "missing $WORKFLOW" >&2
  exit 1
}

pinned=$(grep -oE 'rvben/rumdl/releases/download/v[0-9]+\.[0-9]+\.[0-9]+' "$WORKFLOW" | head -1 | sed -E 's|.*/v||')
if [[ -z "$pinned" ]]; then
  echo "could not find a pinned rumdl version in $WORKFLOW — parsing likely broke" >&2
  exit 1
fi

if ! command -v rumdl &>/dev/null; then
  echo "WARNING: rumdl is not installed; CI pins v$pinned" >&2
  exit 0
fi

local_version=$(rumdl --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [[ "$local_version" == "$pinned" ]]; then
  echo "rumdl $local_version matches CI"
else
  echo "WARNING: local rumdl is ${local_version:-unknown} but CI pins v$pinned." >&2
  echo "         Markdown lint results can differ between the two; a pass here" >&2
  echo "         does not guarantee CI passes. Install v$pinned to match." >&2
fi
exit 0
