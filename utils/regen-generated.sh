#!/usr/bin/env bash
# regen-generated.sh — regenerate (or verify) every generated tree, in order.
#
# Several directories are derived from hand-edited sources. Editing a source
# without regenerating them fails CI, so this is the one command to run:
#
#   1. utils/sync.sh                 vendored utils -> plugins-*/**/scripts/
#   2. utils/port-session-skills.py  Claude session skills -> plugins-opencode/session/
#   3. utils/skills-catalog.py       OpenCode skills -> skills-catalog/
#
# The order matters: the catalog is built from plugins-opencode/, which the
# port and the vendoring step feed, so a later stage must see earlier output.
#
# Usage:
#   utils/regen-generated.sh           # regenerate all three, in order
#   utils/regen-generated.sh --check   # exit non-zero on any drift, no writes
#
# --check runs every stage even after one drifts, so one run reports them all.
# Regenerating stops at the first failing stage: later stages read earlier output.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-regen}"

case "$MODE" in
  regen | --check) ;;
  *)
    echo "usage: $0 [--check]" >&2
    exit 2
    ;;
esac

if [[ "$MODE" == "--check" ]]; then
  flag="--check"
else
  flag=""
fi

rc=0
run() {
  local label="$1"
  shift
  echo "== $label"
  if ! "$@"; then
    [[ "$MODE" == "--check" ]] || exit 1
    rc=1
  fi
}

# ${flag:+...} expands to nothing when regenerating, so each tool runs bare.
run "vendored utils (sync.sh)" bash "$ROOT/utils/sync.sh" ${flag:+"$flag"}
run "opencode session port (port-session-skills.py)" python3 "$ROOT/utils/port-session-skills.py" ${flag:+"$flag"}
run "skills catalog (skills-catalog.py)" python3 "$ROOT/utils/skills-catalog.py" ${flag:+"$flag"}

if [[ $rc -ne 0 ]]; then
  if [[ "$MODE" == "--check" ]]; then
    echo "" >&2
    echo "generated trees are out of date: run utils/regen-generated.sh and stage the result." >&2
  fi
  exit 1
fi
