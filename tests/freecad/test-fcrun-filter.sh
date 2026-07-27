#!/usr/bin/env bash
# test-fcrun-filter.sh — guard fcrun's output filter against eating real data.
#
# FreeCAD writes its progress markers with NO trailing newline, so they arrive
# glued to the front of whatever real output comes next:
#
#     Recompute......  T_BayR_Upper_Bottom  491.0 x 251.1 x 6.0
#
# The filter used to be a pure line-oriented `grep -v`, which failed both ways:
# with the marker at line start the anchored pattern matched and -v dropped the
# whole line, cut-list row and all (silent data loss -- a missing row reads as a
# part that is not in the model); with the marker mid-line the anchor missed and
# the noise survived into generated files.
#
# So these tests assert the two halves of the contract separately: noise is
# stripped as a SUBSTRING, and the data sharing its line is kept.
#
# Needs no FreeCAD -- filter() is awk and grep only, so this runs everywhere.
#
# Usage: bash tests/freecad/test-fcrun-filter.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FCRUN="$ROOT/plugins-claude/freecad/scripts/fcrun"

PASS=0
FAIL=0
SKIP=0

pass() {
  printf "  \033[32m✓\033[0m %s\n" "$1"
  ((PASS++)) || true
}

fail() {
  printf "  \033[31m✗\033[0m %s\n      %s\n" "$1" "$2"
  ((FAIL++)) || true
}

if [[ ! -r "$FCRUN" ]]; then
  echo "  - SKIP: fcrun not readable at $FCRUN"
  echo "Total: 0  PASS: 0  FAIL: 0  SKIP: 1"
  exit 0
fi

# Pull the real filter() out of fcrun rather than reimplementing it -- a copy
# would drift and then test nothing.
FILTER_SRC="$(sed -n '/^filter() {/,/^}/p' "$FCRUN")"
if [[ -z "$FILTER_SRC" ]]; then
  fail "extract filter() from fcrun" "no 'filter() {' ... '}' block found"
  echo "Total: 1  PASS: 0  FAIL: 1  SKIP: 0"
  exit 1
fi
eval "$FILTER_SRC"

# `|| true`: the filter ends in `grep -v`, which exits 1 when it drops every
# line. That is the CORRECT outcome for a noise-only input, so without this the
# `dropped` cases would kill the script under `set -e -o pipefail`.
run_filter() { printf '%s\n' "$1" | filter || true; }

# kept <label> <input> <substring that must survive>
kept() {
  local label="$1" input="$2" want="$3" got
  got="$(run_filter "$input")"
  if [[ "$got" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label" "wanted to keep '$want', got '$got'"
  fi
}

# dropped <label> <input>
dropped() {
  local label="$1" input="$2" got
  got="$(run_filter "$input")"
  if [[ -z "$got" ]]; then
    pass "$label"
  else
    fail "$label" "expected nothing, got '$got'"
  fi
}

# gone <label> <input> <substring that must NOT survive>
gone() {
  local label="$1" input="$2" bad="$3" got
  got="$(run_filter "$input")"
  if [[ "$got" != *"$bad"* ]]; then
    pass "$label"
  else
    fail "$label" "'$bad' should have been stripped, got '$got'"
  fi
}

echo "fcrun output filter"

# --- the regression this file exists for --------------------------------------
GLUED='Recompute......  T_BayR_Upper_Bottom  491.0 x 251.1 x 6.0'
kept "glued Recompute keeps the cut-list row" "$GLUED" "T_BayR_Upper_Bottom  491.0 x 251.1 x 6.0"
gone "glued Recompute is itself stripped" "$GLUED" "Recompute"

GLUED2='Checking topology...A_Bottom 1005.0 x 545.0'
kept "glued topology check keeps its row" "$GLUED2" "A_Bottom 1005.0 x 545.0"
gone "glued topology check is stripped" "$GLUED2" "Checking topology"

GLUED3='Checking for self-intersections......CLASH     0 interference pair(s)'
kept "glued self-intersection check keeps CLASH" "$GLUED3" "CLASH     0 interference pair(s)"

GLUED4="$(printf '\t(20 %%)\t(40 %%)  BUY       2 x 4x8')"
kept "glued percent progress keeps the BUY line" "$GLUED4" "BUY       2 x 4x8"
gone "glued percent progress is stripped" "$GLUED4" "(20 %)"

# --- noise-only lines still go away ------------------------------------------
dropped "progress-only line" "$(printf '\t(20 %%)\t(40 %%)\t(60 %%)')"
dropped "Recompute-only line" 'Recompute......'
dropped "env dump line" 'PYTHONPATH=/app/lib/python3'
dropped "SpaceMouse noise" '3Dconnexion driver not found'
dropped "Navlib noise" 'Navlib: init failed'
dropped "launcher line" 'Running: /app/bin/freecad'
dropped "console banner" '[FreeCAD Console mode]'
dropped "bare prompt" '>>> '
dropped "blank line" ''
dropped "whitespace-only line" '   '

# --- real output must survive untouched --------------------------------------
kept "plain report line" 'CLASH     0 interference pair(s)' 'CLASH     0 interference pair(s)'
kept "say() output" 'part C top   450.0   saw table 810.0' 'part C top   450.0   saw table 810.0'

# The percent guard keys on "(NN %)" -- digits, space, percent -- so a genuine
# percentage written without the space must NOT be treated as progress spew.
kept "percentage without a space is not progress" \
  '300 g total (30% of a 1kg spool)' '300 g total (30% of a 1kg spool)'
kept "filament grams line" '  filament  42 g (0.14 spool)' 'filament  42 g'

# A part whose name merely contains a keyword must not be harmed.
kept "part named like a keyword" '  S_Back_Recompute_Test 100.0' 'S_Back_Recompute_Test 100.0'

echo "Total: $((PASS + FAIL))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
[[ "$FAIL" -eq 0 ]]
