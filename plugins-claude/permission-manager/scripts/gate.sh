#!/usr/bin/env bash
# gate.sh — permission-manager v3 PreToolUse hook for the Bash tool.
#
# Decides deterministically for the cases it can prove, before the model-based
# auto-mode classifier:
#   allow  — every executed unit is provably read-only
#   ask    — some unit matches a danger rule (sends the call to the user's prompt),
#            or the command is too large to analyse in time (oversize)
#   (none) — anything else, including every error: print nothing, exit 0
#
# One shfmt --tojson parse and one jq run (engine.jq + rules/*.json) per command.
# Program text handed to bash -c / eval / watch / env -S or piped into a shell is
# re-parsed (up to depth 4) for danger rules only; it can never produce an allow.
#
# This script never executes the command it classifies, and never exits non-zero.

trap 'exit 0' EXIT
set -u

HERE="${BASH_SOURCE[0]%/*}"
[[ "$HERE" == "${BASH_SOURCE[0]}" ]] && HERE=.
ENGINE="$HERE/engine.jq"
CHECK="$HERE/check.jq"
RULES="$HERE/rules"
MAX_CMD_BYTES=20000
MAX_AST_BYTES=8388608
MAX_OPS=1500
MAX_DEPTH=4
MAX_PAYLOADS=16
MAX_PATHS=128
MAX_PATH_BYTES=32768

# Operator probe, parsed in the same shfmt run as the command: shfmt encodes
# operators as integers before v3.14 and as strings since, so engine.jq reads
# the encoding from these five statements and then drops them. Keep in sync
# with the probe block at the top of engine.jq.
PROBE=': >p >>p &>p &>>p >|p <>p >&2 <&0 <p <<<p <<P1 <<-P2
P1
P2
: | :
: |& :
: && :
: || :
'

# Hooks may run with a restricted PATH; probe common user-local install dirs.
if [[ -z "${PM_GATE_NO_PROBE:-}" ]] && { ! command -v shfmt >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; }; then
  for _d in "$HOME/.local/bin" "$HOME/go/bin" "$HOME/bin" /usr/local/bin /opt/homebrew/bin; do
    [[ -d "$_d" ]] && PATH="$PATH:$_d"
  done
  unset _d
fi

TO=() TP=()
command -v timeout >/dev/null 2>&1 && TO=(timeout 5) TP=(timeout 3)
HAVE_HEAD=0
command -v head >/dev/null 2>&1 && HAVE_HEAD=1

INPUT=""
IFS= read -r -d '' INPUT || true

# Missing dependency: pass through, with one stderr note per session.
note_missing() {
  local sid="nosession" dir marker
  [[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_.-]+)\" ]] && sid="${BASH_REMATCH[1]}"
  dir="${TMPDIR:-/tmp}/permission-manager-${UID:-0}"
  marker="$dir/missing-$1-$sid"
  [[ -e "$marker" ]] && return 0
  mkdir -p "$dir" 2>/dev/null && : >"$marker" 2>/dev/null
  echo "permission-manager: $1 not found; Bash commands pass through unclassified (install shfmt >= 3 and jq)" >&2
}
for _dep in jq shfmt; do
  if ! command -v "$_dep" >/dev/null 2>&1; then
    note_missing "$_dep"
    exit 0
  fi
done
unset _dep

# One jq pass over the hook payload: tool, mode, cwd, command (NUL separated).
mapfile -d '' -t F < <(printf '%s' "$INPUT" | "${TO[@]}" jq -j '
  [(.tool_name // ""), (.permission_mode // ""), (.cwd // ""), (.tool_input.command // "")]
  | map(tostring | gsub("\u0000"; "")) | join("\u0000") + "\u0000"' 2>/dev/null)
[[ ${#F[@]} -eq 4 ]] || exit 0
TOOL="${F[0]}" MODE="${F[1]}" HOOK_CWD="${F[2]}" CMD="${F[3]}"

[[ "$TOOL" == "Bash" ]] || exit 0
[[ "$MODE" == "bypassPermissions" ]] && exit 0
[[ -n "${CMD//[[:space:]]/}" ]] || exit 0
[[ -n "$HOOK_CWD" ]] || HOOK_CWD="$PWD"
[[ "$HOOK_CWD" == /* ]] || exit 0

BASE_ARGS=(-L "$HERE" --arg cmd "$CMD" --arg cwd "$HOOK_CWD" --arg home "${HOME:-/nonexistent}"
  --slurpfile paths "$RULES/paths.json" --slurpfile danger "$RULES/danger.json")
JQ_ARGS=("${BASE_ARGS[@]}" --slurpfile tools "$RULES/tools.json"
  --slurpfile allow "$RULES/allow.json" --slurpfile regex "$RULES/regex.json")

# check_res — validate RES (NUL-separated engine items) after an engine run.
check_res() {
  [[ ${#RES[@]} -ge 5 && "${RES[-1]}" == END ]] || return 1
  unset "RES[-1]"
  case "${RES[0]}" in ALLOW | ASK | DENY | PASS | OK) ;; *) return 1 ;; esac
  [[ -n "${PM_GATE_DEBUG:-}" ]] && printf 'engine: %s %s\n' "${RES[0]}" "${RES[1]}" >&2
  if [[ "${RES[0]}" != PASS && "${RES[0]}" != OK && "${RES[2]}" != '{"hookSpecificOutput":'* ]]; then
    return 1
  fi
  return 0
}

# oversize WHY — sets RES to an ASK: a command too large to analyse within the
# hook timeout must not lose a danger ask by falling through. Never an allow.
oversize() {
  RES=()
  # shellcheck disable=SC2016 # $why is a jq variable
  mapfile -d '' -t RES < <("${TO[@]}" jq -n -j -L "$HERE" "${BASE_ARGS[@]}" --arg why "$1" \
    'include "pathclass"; render("ASK"; "permission-manager: command too large to analyse (" + $why + ") [oversize]"; [])' 2>/dev/null)
  check_res
}

# classify TEXT DEPTH — sets RES; non-zero on failure. shfmt indents its JSON
# by nesting depth, so a long pipeline or deep nesting is quadratic in time and
# size. Each of these is an oversize ask, never a passthrough that would lose a
# danger ask: output over MAX_AST_BYTES (the end marker is cut off), a parse
# over the TP time limit (timeout's 124), and shfmt's own nesting limit.
classify() {
  local ast rc
  RES=()
  if ((HAVE_HEAD)); then
    ast=$({
      "${TP[@]}" shfmt -ln bash --tojson <<<"$PROBE$1" 2>&1 || printf '\n#PMRC%s' "$?"
      printf '\n#PMEND'
    } |
      head -c "$MAX_AST_BYTES")
    if [[ "$ast" != *$'\n#PMEND' ]]; then
      local LC_ALL=C # byte length
      ((${#ast} >= MAX_AST_BYTES)) || return 1
      oversize "syntax tree over $((MAX_AST_BYTES / 1048576)) MB"
      return
    fi
    ast=${ast%$'\n#PMEND'}
  else
    ast=$("${TP[@]}" shfmt -ln bash --tojson <<<"$PROBE$1" 2>&1) || ast+=$'\n#PMRC'"$?"
  fi
  if [[ "$ast" == *$'\n#PMRC'* ]]; then
    rc=${ast##*$'\n#PMRC'}
    if [[ "$rc" == 124 ]]; then
      oversize "parse over ${TP[1]:-?} s"
      return
    elif [[ "$ast" == *"exceeded max depth"* ]]; then
      oversize "nesting too deep to parse"
      return
    fi
    return 1
  fi
  [[ "$ast" == \{* ]] || return 1
  mapfile -d '' -t RES < <("${TO[@]}" jq -j -f "$ENGINE" --arg depth "$2" "${JQ_ARGS[@]}" <<<"$ast" 2>/dev/null)
  check_res
}

# resolve_check ITEM... — ITEM is "K<TAB>path" (K = r, a, x or w). Resolves every
# path (plus $HOME, the cwd and /tmp) with ONE realpath call, then classifies the
# results with ONE engine run in check mode. An operand of a recursive reader
# (a) that does not resolve to a directory is an ordinary read (r). Sets RES;
# non-zero on any failure or overflow.
resolve_check() {
  local -a paths=() out=() args=()
  local total=0 i n k
  (($# <= MAX_PATHS)) || return 1
  for i in "$@"; do
    paths+=("${i#*$'\t'}")
    total=$((total + ${#i}))
  done
  ((total <= MAX_PATH_BYTES)) || return 1
  command -v realpath >/dev/null 2>&1 || return 1
  mapfile -d '' -t out < <(
    "${TO[@]}" realpath -m -z -- "${paths[@]}" "${HOME:-/nonexistent}" "$HOOK_CWD" /tmp 2>/dev/null
    printf 'rc=%s\0' "$?"
  )
  n=$#
  [[ ${#out[@]} -eq $((n + 4)) && "${out[-1]}" == rc=0 ]] || return 1
  for ((i = 0; i <= n + 2; i++)); do
    [[ "${out[i]}" == /* ]] || return 1
  done
  i=0
  for item in "$@"; do
    k="${item%%$'\t'*}"
    [[ "$k" == a && ! -d "${out[i]}" ]] && k=r
    args+=("$k"$'\t'"${out[i]}")
    i=$((i + 1))
  done
  RES=()
  mapfile -d '' -t RES < <("${TO[@]}" jq -n -j -f "$CHECK" --arg rhome "${out[n]}" \
    --arg rcwd "${out[n + 1]}" --arg rtmp "${out[n + 2]}" \
    "${BASE_ARGS[@]}" --args "${args[@]}" 2>/dev/null)
  check_res
}

# git_clean DIR — true only if DIR is inside a git repo whose repo-local config
# (includes followed) sets none of the keys that make read-only git commands
# run programs. One git call; global/system config are not consulted.
GIT_EXEC_KEYS='^(core\.(fsmonitor|pager|editor|sshcommand|hookspath|askpass|gitproxy|attributesfile|worktree|alternaterefscommand)|sequence\.editor|diff\..*\.(textconv|command)|diff\.external|filter\..*|merge\..*\.driver|credential\..*helper|alias\..*|include\..*|includeif\..*|pager\..*|gpg\..*program|uploadpack\.packobjectshook|remote\..*\.(uploadpack|receivepack|proxy)|protocol\.(ext\.)?allow|url\..*\.(insteadof|pushinsteadof)|submodule\..*|extensions\.worktreeconfig)$'
git_clean() {
  local rc=0
  command -v git >/dev/null 2>&1 || return 1
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    "${TO[@]}" git -C "$1" config --local --includes --get-regexp "$GIT_EXEC_KEYS" \
    </dev/null >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 1 ]] # 1 = no such key; 0 = a key matched; 128 = not a repo / error
}

emit() { # emit HOOK_JSON AUDIT_JSON
  local log="${PERMISSION_AUDIT_LOG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/permission-audit.jsonl}"
  # Private log: created under umask 077 (file 600, new dirs 700); an existing
  # regular file we own is narrowed to 600 (never through a symlink).
  if [[ -n "$2" ]]; then
    umask 077
    [[ -d "${log%/*}" ]] || mkdir -p "${log%/*}" 2>/dev/null
    if [[ -f "$log" && ! -L "$log" && -O "$log" ]]; then
      chmod 600 "$log" 2>/dev/null
    fi
    printf '%s\n' "$2" >>"$log" 2>/dev/null
  fi
  printf '%s\n' "$1"
  exit 0
}

# split_extras DEPTH REMOTE — sort the tagged engine items in RES[4..].
split_extras() {
  local i item tag
  for ((i = 4; i < ${#RES[@]}; i++)); do
    item="${RES[i]}"
    tag="${item%%$'\t'*}"
    case "$tag" in
      p) ((${1} < MAX_DEPTH)) && queue+=("$(($1 + 1))"$'\t'"$2"$'\t'"${item#*$'\t'}") ;;
      s) ((${1} < MAX_DEPTH)) && queue+=("$(($1 + 1))"$'\t'1$'\t'"${item#*$'\t'}") ;;
      r | a | x) cands+=("$item") ;;
      g) gits+=("${item#*$'\t'}") ;;
      w) [[ "$2" == 0 ]] && writes+=("$item") ;;
    esac
  done
}

queue=() cands=() gits=() writes=()
RES=()
if ((${#CMD} > MAX_CMD_BYTES)); then
  oversize "over $MAX_CMD_BYTES characters" && emit "${RES[2]}" "${RES[3]}"
  exit 0
fi
# Each | or & usually nests the syntax tree one level deeper (see classify):
# skip a parse that would take seconds.
_ops=${CMD//[^|&]/}
if ((${#_ops} > MAX_OPS)); then
  oversize "over $MAX_OPS pipe and list operators" && emit "${RES[2]}" "${RES[3]}"
  exit 0
fi
unset _ops
classify "$CMD" 0 || exit 0
case "${RES[0]}" in
  ASK | DENY) emit "${RES[2]}" "${RES[3]}" ;;
esac
split_extras 0 0

if [[ "${RES[0]}" == ALLOW ]]; then
  hook="${RES[2]}" audit="${RES[3]}"
  if ((${#gits[@]} > 0)); then
    ((${#gits[@]} == 1)) || exit 0
    git_clean "${gits[0]}" || exit 0
  fi
  if ((${#cands[@]} > 0)); then
    resolve_check "${cands[@]}" || exit 0
    [[ "${RES[0]}" == OK ]] || exit 0
  fi
  emit "$hook" "$audit"
fi

# PASS: re-parse program-text payloads for danger rules (breadth first). A
# payload of ssh/mosh is remote: its write targets are not resolved locally.
seen=0
while ((${#queue[@]} > 0 && seen < MAX_PAYLOADS)); do
  item="${queue[0]}"
  queue=("${queue[@]:1}")
  seen=$((seen + 1))
  depth="${item%%$'\t'*}"
  rest="${item#*$'\t'}"
  remote="${rest%%$'\t'*}"
  text="${rest#*$'\t'}"
  [[ -n "$text" ]] || continue
  classify "$text" "$depth" || continue
  case "${RES[0]}" in
    ASK | DENY) emit "${RES[2]}" "${RES[3]}" ;;
  esac
  cands=() gits=()
  split_extras "$depth" "$remote"
done

# Write targets of a PASS: promote to ASK when a symlink makes one resolve to a
# persistence, registry-config, device or kernel-trigger path.
if ((${#writes[@]} > 0)) && resolve_check "${writes[@]}" && [[ "${RES[0]}" == ASK ]]; then
  emit "${RES[2]}" "${RES[3]}"
fi
exit 0
