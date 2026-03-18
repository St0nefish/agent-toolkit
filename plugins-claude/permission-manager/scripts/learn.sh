#!/usr/bin/env bash
# learn.sh — Analyze permission audit log and suggest allow-list patterns.
#
# Subcommands:
#   scan     — Read audit log, extract unique ask-decision commands, sort by frequency.
#              Options: --project <name>  Filter by project basename
#                       --since <days>    Only include entries from last N days (default: 30)
#   suggest  — Read commands from stdin (one per line), output JSON pattern suggestions.
#
# Pipeline:  learn.sh scan | learn.sh suggest

set -euo pipefail

AUDIT_LOG="${PERMISSION_AUDIT_LOG:-${HOME}/.claude/permission-audit.jsonl}"

usage() {
  cat <<'EOF'
Usage: learn.sh <subcommand> [options]

Subcommands:
  scan      Read audit log and output unique commands (most frequent first)
              --decision <type>  Filter by decision: ask (default), allow, deny, or all
              --project <name>   Filter by project basename
              --since <days>     Only include entries from last N days (default: 30)
  suggest   Read commands from stdin, output JSON array of suggested patterns

Pipeline: learn.sh scan | learn.sh suggest
EOF
  exit 0
}

# --- scan subcommand ---
do_scan() {
  local project_filter="" since_days=30 decision_filter="ask"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        project_filter="$2"
        shift 2
        ;;
      --since)
        since_days="$2"
        shift 2
        ;;
      --decision)
        decision_filter="$2"
        shift 2
        ;;
      -h | --help) usage ;;
      *)
        echo "Error: Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$AUDIT_LOG" ]]; then
    exit 0
  fi

  local cutoff_ts=""
  if [[ "$since_days" -gt 0 ]]; then
    if date -v-1d +%s &>/dev/null 2>&1; then
      # macOS date
      cutoff_ts=$(date -v-"${since_days}d" -u +%Y-%m-%dT%H:%M:%SZ)
    else
      # GNU date
      cutoff_ts=$(date -u -d "$since_days days ago" +%Y-%m-%dT%H:%M:%SZ)
    fi
  fi

  local jq_filter
  if [[ "$decision_filter" == "all" ]]; then
    jq_filter="true"
  else
    jq_filter=".decision == \"$decision_filter\""
  fi
  if [[ -n "$project_filter" ]]; then
    jq_filter="$jq_filter and .project == \"$project_filter\""
  fi
  if [[ -n "$cutoff_ts" ]]; then
    jq_filter="$jq_filter and .ts >= \"$cutoff_ts\""
  fi

  # Extract commands, count frequency, sort descending, output unique commands
  jq -r "select($jq_filter) | .command" "$AUDIT_LOG" 2>/dev/null |
    sort | uniq -c | sort -rn | awk '{$1=$1; sub(/^[0-9]+ /, ""); print}'
}

# --- suggest subcommand ---
#
# Pattern inference algorithm:
#   1. Group commands by first token (tool name)
#   2. For groups with 1 command: use first-two-token prefix pattern
#   3. For groups with 2+ commands: compute ordered token skeleton (greedy LCS)
#   4. If skeleton is too short (≤1 token), sub-group by second token and retry
#   5. Build glob pattern: t1 *t2 *t3 ... *tn [*]
#
# Pattern format: `t1 *t2 *t3 *`
#   Each `*tokenN` matches the token preceded by any characters (including
#   optional flags or arguments). The space after each token acts as a word
#   boundary, preventing partial-word matches like "catalog" matching "cat".
#   Trailing ` *` is appended when input commands have args after the last
#   skeleton token; omitted when all commands end with it.

# Compute the common ordered token subsequence across a set of commands.
# Reads commands from stdin (one per line), outputs skeleton tokens one per line.
# Uses a greedy approach: starts with the first command's tokens, then iteratively
# intersects with each subsequent command, keeping only tokens that appear in both
# in the same relative order.
compute_skeleton() {
  local -a skeleton=()
  local first=true

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    local -a tokens
    read -ra tokens <<<"$cmd"

    if [[ "$first" == true ]]; then
      skeleton=("${tokens[@]}")
      first=false
      continue
    fi

    # Intersect skeleton with current command's tokens, preserving order
    local -a new_skeleton=()
    local j=0
    for ((i = 0; i < ${#skeleton[@]}; i++)); do
      for ((k = j; k < ${#tokens[@]}; k++)); do
        if [[ "${tokens[$k]}" == "${skeleton[$i]}" ]]; then
          new_skeleton+=("${skeleton[$i]}")
          j=$((k + 1))
          break
        fi
      done
    done
    skeleton=("${new_skeleton[@]}")
  done

  printf '%s\n' "${skeleton[@]}"
}

# Build a glob pattern from skeleton tokens.
# Format: t1 *t2 *t3 ... *tn [trailing]
# The `*` before each token (after the first) absorbs any variable content
# between fixed tokens — flags, container names, paths, etc.
build_pattern_from_skeleton() {
  local -a skeleton=("$@")

  if [[ ${#skeleton[@]} -eq 0 ]]; then
    echo "*"
    return
  fi

  local pattern="${skeleton[0]}"
  for ((i = 1; i < ${#skeleton[@]}; i++)); do
    pattern+=" *${skeleton[$i]}"
  done

  echo "$pattern"
}

# Check whether any command has tokens after the last skeleton token.
# Returns 0 (true) if trailing content exists, 1 if all commands end with the skeleton.
has_trailing_content() {
  local last_skel="$1"
  shift
  local -a cmds=("$@")

  for cmd in "${cmds[@]}"; do
    local -a tokens
    read -ra tokens <<<"$cmd"
    if [[ "${tokens[${#tokens[@]}-1]}" != "$last_skel" ]]; then
      return 0
    fi
  done
  return 1
}

# Process a group of commands: compute skeleton, build pattern, determine broadness.
# Outputs a JSON object with pattern, skeleton, commands, broad fields.
process_group() {
  local -a group_cmds=("$@")

  # Single command: use first-two-token prefix pattern
  if [[ ${#group_cmds[@]} -eq 1 ]]; then
    local t1 t2
    read -r t1 t2 _ <<<"${group_cmds[0]}"
    t2="${t2:-}"

    local pattern broad="false" skel_json
    if [[ -n "$t2" ]]; then
      pattern="${t1} ${t2} *"
      skel_json=$(jq -nc --arg a "$t1" --arg b "$t2" '[$a, $b]')
    else
      pattern="${t1} *"
      broad="true"
      skel_json=$(jq -nc --arg a "$t1" '[$a]')
    fi

    local cmds_json
    cmds_json=$(printf '%s\n' "${group_cmds[@]}" | jq -Rnc '[inputs | select(length > 0)]')
    jq -nc --arg p "$pattern" --argjson s "$skel_json" --argjson b "$broad" --argjson c "$cmds_json" \
      '{pattern: $p, skeleton: $s, commands: $c, broad: $b}'
    return
  fi

  # Multiple commands: compute skeleton
  local -a skeleton=()
  local skel_line
  while IFS= read -r skel_line; do
    [[ -z "$skel_line" ]] && continue
    skeleton+=("$skel_line")
  done < <(printf '%s\n' "${group_cmds[@]}" | compute_skeleton)

  local broad="false"

  # If skeleton is too short, mark as broad
  if [[ ${#skeleton[@]} -le 1 ]]; then
    broad="true"
  fi

  local pattern
  pattern=$(build_pattern_from_skeleton "${skeleton[@]}")

  # Append trailing ` *` if commands have args after the last skeleton token
  if [[ ${#skeleton[@]} -gt 0 ]]; then
    local last_skel="${skeleton[${#skeleton[@]}-1]}"
    if has_trailing_content "$last_skel" "${group_cmds[@]}"; then
      pattern+=" *"
    fi
  else
    pattern+=" *"
  fi

  local skel_json
  skel_json=$(printf '%s\n' "${skeleton[@]}" | jq -Rnc '[inputs | select(length > 0)]')
  local cmds_json
  cmds_json=$(printf '%s\n' "${group_cmds[@]}" | jq -Rnc '[inputs | select(length > 0)]')

  jq -nc --arg p "$pattern" --argjson s "$skel_json" --argjson b "$broad" --argjson c "$cmds_json" \
    '{pattern: $p, skeleton: $s, commands: $c, broad: $b}'
}

do_suggest() {
  local -a commands=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    commands+=("$line")
  done

  if [[ ${#commands[@]} -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  # --- Step 1: Group by first token ---
  declare -A first_token_cmds=() # key=tok1, value=cmd1$'\n'cmd2...
  for cmd in "${commands[@]}"; do
    local tok1
    read -r tok1 _ <<<"$cmd"
    if [[ -n "${first_token_cmds[$tok1]:-}" ]]; then
      first_token_cmds[$tok1]+=$'\n'"$cmd"
    else
      first_token_cmds[$tok1]="$cmd"
    fi
  done

  local result="[]"

  for tok1 in "${!first_token_cmds[@]}"; do
    # Parse group commands into array
    local -a group_cmds=()
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      group_cmds+=("$cmd")
    done <<<"${first_token_cmds[$tok1]}"

    # --- Step 2: Try full-group skeleton first ---
    local full_entry
    full_entry=$(process_group "${group_cmds[@]}")
    local full_broad
    full_broad=$(echo "$full_entry" | jq -r '.broad')
    local full_skel_len
    full_skel_len=$(echo "$full_entry" | jq '.skeleton | length')

    # --- Step 3: If skeleton is too short and group has 3+ commands, sub-group ---
    if [[ "$full_skel_len" -le 1 && ${#group_cmds[@]} -ge 2 ]]; then
      # Sub-group by second token
      declare -A subgroups=()
      for cmd in "${group_cmds[@]}"; do
        local t2
        read -r _ t2 _ <<<"$cmd"
        t2="${t2:-_none_}"
        if [[ -n "${subgroups[$t2]:-}" ]]; then
          subgroups[$t2]+=$'\n'"$cmd"
        else
          subgroups[$t2]="$cmd"
        fi
      done

      # Only use sub-groups if they produce better patterns than the broad one
      local use_subgroups=false
      if [[ ${#subgroups[@]} -gt 1 ]]; then
        use_subgroups=true
      fi

      if [[ "$use_subgroups" == true ]]; then
        for t2 in "${!subgroups[@]}"; do
          local -a sub_cmds=()
          while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            sub_cmds+=("$cmd")
          done <<<"${subgroups[$t2]}"

          local sub_entry
          sub_entry=$(process_group "${sub_cmds[@]}")
          result=$(echo "$result" | jq --argjson e "$sub_entry" '. += [$e]')
        done
      else
        result=$(echo "$result" | jq --argjson e "$full_entry" '. += [$e]')
      fi
      unset subgroups
    else
      result=$(echo "$result" | jq --argjson e "$full_entry" '. += [$e]')
    fi
  done

  # Deduplicate by pattern, merging commands
  result=$(echo "$result" | jq '
    group_by(.pattern) | map(
      reduce .[] as $item (null;
        if . == null then $item
        else .commands += $item.commands | .broad = (.broad or $item.broad)
        end
      )
    )
  ')

  echo "$result" | jq '.'
}

# --- Main dispatch ---
subcommand="${1:-}"
shift || true

case "$subcommand" in
  scan) do_scan "$@" ;;
  suggest) do_suggest ;;
  -h | --help) usage ;;
  *)
    echo "Error: subcommand required (scan, suggest)" >&2
    usage
    ;;
esac
