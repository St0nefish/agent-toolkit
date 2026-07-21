#!/usr/bin/env bash
# test-model.sh — exercise the Model surface _cutplan_probe.py does not touch:
# joinery primitives, checks (clashes/printable/gap/envelope), filament,
# multi-rider rip_with folding, and imperial unit formatting. The wwcut logic
# is unit-tested headlessly in test-wwcut.sh; this covers the wwkit layer that
# needs a real FreeCAD to build parts and shapes.
#
# FreeCAD is not present in CI, so this SKIPs cleanly (exit 0) when it is absent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FCRUN="$ROOT/plugins-claude/freecad/scripts/fcrun"

# Locate FreeCAD the way fcrun does; skip if it is not installed.
FC="${FREECAD_BIN:-}"
if [[ -z "$FC" ]]; then
  for c in \
    /Applications/FreeCAD.app/Contents/MacOS/FreeCAD \
    "$HOME/Applications/FreeCAD.app/Contents/MacOS/FreeCAD" \
    freecad FreeCAD freecadcmd FreeCADCmd; do
    if [[ -x "$c" ]] || command -v "$c" >/dev/null 2>&1; then
      FC="$c"
      break
    fi
  done
fi

if [[ -z "$FC" ]]; then
  echo "  - SKIP: FreeCAD not found (model integration test needs it)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export WW_OUT="$TMP"
export WW_LOG="$TMP/log.txt"

if "$FCRUN" "$SCRIPT_DIR/_model_probe.py" >"$TMP/out.txt" 2>&1 &&
  grep -q "MODEL PROBE OK" "$TMP/log.txt" 2>/dev/null; then
  echo "  ✓ model wiring: joinery, checks, filament, multi-rider rip_with, imperial units"
  exit 0
fi

echo "  ✗ model integration probe failed" >&2
echo "--- fcrun output ---" >&2
cat "$TMP/out.txt" >&2 || true
exit 1
