#!/usr/bin/env bash
# explain.sh — Classification trace for a single Bash command.
# Shows which classifiers fire, what decision each makes, and the final aggregate.
#
# Usage: bash explain.sh <command>
#
# Sources the same lib-classify.sh and classifiers as cmd-gate.sh, then
# instruments classify_single_command to capture per-classifier traces.
#
# NOTE: Classifier dispatch order is duplicated from lib-classify.sh
# (classify_single_command, lines 123-168). If classifiers are added or
# reordered there, update the CLASSIFIERS array here too.

set -euo pipefail

ALLOW_EDIT_ACTIVE=0

# Parse flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    --allow-edit)
      ALLOW_EDIT_ACTIVE=1
      shift
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done
export ALLOW_EDIT_ACTIVE

command_arg="${1:-}"
if [[ -z "$command_arg" ]]; then
  echo "Usage: explain.sh [--allow-edit] <command>"
  echo "  Traces the cmd-gate classification pipeline for a command."
  echo "  --allow-edit  Simulate allow-edits permission mode"
  exit 0
fi

# --- Dependency check ---
missing=()
command -v shfmt &>/dev/null || missing+=("shfmt")
command -v jq &>/dev/null || missing+=("jq")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required dependencies: ${missing[*]}"
  echo "Run /permissions setup to install."
  exit 0
fi

# --- Probe shfmt redirect Op codes (same logic as cmd-gate.sh lines 61-64) ---
SHFMT_OP_GT=$(printf '%s' 'x > /tmp/x' | shfmt --tojson 2>/dev/null |
  jq '.. | objects | select(.Redirs?) | .Redirs[0].Op' 2>/dev/null || echo "")
SHFMT_OP_APPEND=$(printf '%s' 'x >> /tmp/x' | shfmt --tojson 2>/dev/null |
  jq '.. | objects | select(.Redirs?) | .Redirs[0].Op' 2>/dev/null || echo "")

if [[ -z "$SHFMT_OP_GT" || -z "$SHFMT_OP_APPEND" ]]; then
  echo "ERROR: Failed to probe shfmt redirect Op codes."
  exit 0
fi

# --- Source library and classifiers ---
SCRIPTS_DIR="$(dirname "$0")"
# shellcheck source=lib-classify.sh
source "$SCRIPTS_DIR/lib-classify.sh"
for _clf in "$SCRIPTS_DIR/classifiers/"*.sh; do
  # shellcheck disable=SC1090
  source "$_clf"
done
unset _clf

load_custom_patterns
load_allow_edit_commands

# --- Explain trace state ---
declare -a EXPLAIN_TRACE=()
EXPLAIN_LAST_CLASSIFIER=""

# --- Instrument decision helpers to capture trace ---
# Save originals
_orig_allow() { allow "$@"; }
_orig_ask() { ask "$@"; }
_orig_deny() { deny "$@"; }

allow() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=0
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    EXPLAIN_TRACE+=("ALLOW|${EXPLAIN_LAST_CLASSIFIER}|$1")
    return 0
  fi
}

ask() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=1
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    EXPLAIN_TRACE+=("ASK|${EXPLAIN_LAST_CLASSIFIER}|$1")
    return 0
  fi
}

deny() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=2
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    EXPLAIN_TRACE+=("DENY|${EXPLAIN_LAST_CLASSIFIER}|$1")
    return 0
  fi
}

# --- Instrumented classify_single_command ---
# Mirrors the dispatch order in lib-classify.sh (lines 123-168).
# If classifiers are added or reordered there, update this list too.
CLASSIFIERS=(
  check_custom_patterns
  check_allow_edit
  check_find
  check_read_only_tools
  check_git
  check_gradle
  check_gh
  check_tea
  check_docker
  check_npm
  check_pip
  check_cargo
  check_jvm_tools
)

explain_classify_single_command() {
  local command="$1"
  CLASSIFY_RESULT=0
  CLASSIFY_REASON=""
  CLASSIFY_MATCHED=0

  for clf in "${CLASSIFIERS[@]}"; do
    EXPLAIN_LAST_CLASSIFIER="$clf"
    "$clf"
    if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
      return 0
    fi
  done

  # No classifier matched
  EXPLAIN_TRACE+=("NONE|none|no classifier matched — passthrough to built-in permissions")
  return 0
}

# --- Decision label helper ---
decision_label() {
  case "$1" in
    ALLOW) printf "\033[32mALLOW\033[0m" ;;
    ASK) printf "\033[33mASK\033[0m" ;;
    DENY) printf "\033[31mDENY\033[0m" ;;
    NONE) printf "\033[90mNONE\033[0m" ;;
    *) printf "%s" "$1" ;;
  esac
}

# --- Run the trace ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Command: $command_arg"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Redirection check
SEGMENT_MODE=1
EXPLAIN_LAST_CLASSIFIER="check_redirections_ast"
check_redirections_ast "$command_arg"
redir_matched=$CLASSIFY_MATCHED
redir_decision=""
redir_reason=""
if [[ "$redir_matched" -eq 1 ]]; then
  redir_decision="DENY"
  redir_reason="$CLASSIFY_REASON"
  EXPLAIN_TRACE+=("DENY|check_redirections_ast|$CLASSIFY_REASON")
fi
CLASSIFY_RESULT=0
CLASSIFY_REASON=""
CLASSIFY_MATCHED=0

echo "── Redirection check ──"
if [[ "$redir_matched" -eq 1 ]]; then
  printf "  $(decision_label DENY)  %s\n" "$redir_reason"
  echo ""
  echo "── Final decision ──"
  printf "  $(decision_label DENY)  %s\n" "$redir_reason"
  echo ""
  exit 0
else
  printf "  \033[32m✓\033[0m  No unsafe redirections detected\n"
fi
echo ""

# Step 2: Custom patterns check
echo "── Custom patterns ──"
if [[ ${#CUSTOM_ALLOW_PATTERNS[@]} -eq 0 ]]; then
  echo "  (none defined)"
else
  for p in "${CUSTOM_ALLOW_PATTERNS[@]}"; do
    echo "  - $p"
  done
fi
echo ""

# Step 3: Parse segments
echo "── Segments ──"
segments=$(parse_segments "$command_arg")
if [[ -z "$segments" ]]; then
  segments="$command_arg"
  echo "  (single command — no compound parsing needed)"
else
  seg_num=0
  while IFS= read -r seg; do
    [[ -z "$seg" ]] && continue
    ((seg_num++)) || true
    echo "  Segment $seg_num: $seg"
  done <<<"$segments"
  if [[ "$seg_num" -eq 1 ]]; then
    echo "  (single segment)"
  fi
fi
echo ""

# Step 4: Per-segment classification
echo "── Per-segment classification ──"
seg_num=0
worst=0
worst_reason=""
any_classified=0

while IFS= read -r segment; do
  [[ -z "$segment" ]] && continue
  segment=$(echo "$segment" | sed 's/^ *//; s/ *$//')
  [[ -z "$segment" ]] && continue

  ((seg_num++)) || true
  EXPLAIN_TRACE=()
  explain_classify_single_command "$segment"

  if [[ "$seg_num" -gt 1 ]]; then
    echo ""
  fi
  echo "  Segment $seg_num: $segment"

  if [[ ${#EXPLAIN_TRACE[@]} -gt 0 ]]; then
    for entry in "${EXPLAIN_TRACE[@]}"; do
      IFS='|' read -r edecision eclassifier ereason <<<"$entry"
      printf "    $(decision_label "$edecision")  classifier: %-25s reason: %s\n" "$eclassifier" "$ereason"
    done
  fi

  if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
    any_classified=1
    if ((CLASSIFY_RESULT > worst)); then
      worst=$CLASSIFY_RESULT
      worst_reason="$CLASSIFY_REASON"
    elif [[ -z "$worst_reason" && -n "$CLASSIFY_REASON" ]]; then
      worst_reason="$CLASSIFY_REASON"
    fi
  fi
done <<<"$segments"
echo ""

# Step 5: Final aggregate
echo "── Final decision ──"
SEGMENT_MODE=0

if [[ "$any_classified" -eq 0 ]]; then
  printf "  $(decision_label NONE)  No classifier matched — passthrough to built-in permissions\n"
else
  case $worst in
    0) printf "  $(decision_label ALLOW)  %s\n" "$worst_reason" ;;
    1) printf "  $(decision_label ASK)  %s\n" "$worst_reason" ;;
    2) printf "  $(decision_label DENY)  %s\n" "$worst_reason" ;;
  esac
fi
echo ""
