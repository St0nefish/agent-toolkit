#!/bin/bash
set -euo pipefail

# ── Defaults & Constants ─────────────────────────────────────────────────────

DEFAULT_SEGMENTS=(user dir git model context session weekly extra cost)
DEFAULT_SEPARATOR=" | "
DEFAULT_CACHE_TTL=300
DEFAULT_GIT_CACHE_TTL=5
DEFAULT_PATH_MAX_LENGTH=40
DEFAULT_SHOW_HOST="auto"
DEFAULT_GIT_BACKEND="auto"
DEFAULT_LABEL_STYLE="short"
DEFAULT_COST_THRESHOLDS=(5 20)
DEFAULT_EXTRA_HIDE_ZERO=true
DEFAULT_EXTRA_ONLY_BURNING=false
DEFAULT_CURRENCY="$"

# Default colors (256-color codes or keywords)
declare -A DEFAULT_COLORS=(
  [low]=76 [mid]=178 [high]=196
  [separator]=dim
  [git_branch_feature]=76 [git_branch_primary]=178
  [git_staged]=178 [git_unstaged]=196 [git_untracked]=39
  [git_ahead]=76 [git_behind]=196
  [label]=default [model]=default [user]=3 [user_root]=196
  [host]=default [dir]=31
  [reset_time]=default [cost]=76
)

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
CONFIG_FILE="$CONFIG_DIR/config.json"
CREDS_FILE="$HOME/.claude/.credentials.json"
USAGE_CACHE="$CACHE_DIR/usage.json"
GIT_CACHE="$CACHE_DIR/git.cache"
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]') # "darwin" or "linux"

# Populated by load_config / read_stdin
SEGMENTS=()
SEPARATOR=""
CACHE_TTL=0
GIT_CACHE_TTL=0
PATH_MAX_LENGTH=0
SHOW_HOST=""
GIT_BACKEND=""
LABEL_STYLE=""
COST_THRESHOLDS=()
EXTRA_HIDE_ZERO=true
EXTRA_ONLY_BURNING=false
CURRENCY=""
declare -A COLORS=()

MODEL="" CTX_PCT="" COST="" CWD="" PROJECT_DIR=""

# ── Color helpers ─────────────────────────────────────────────────────────────

c() {
  local code="$1"
  case "$code" in
    default) printf '\033[39m' ;;
    reset) printf '\033[0m' ;;
    dim) printf '\033[2m' ;;
    bold) printf '\033[1m' ;;
    [0-9] | [0-9][0-9] | [0-9][0-9][0-9])
      printf '\033[38;5;%dm' "$code"
      ;;
    *) printf '\033[0m' ;;
  esac
}

usage_c() {
  local pct="${1:-0}"
  pct="${pct%%.*}" # strip decimal
  if ((pct >= 80)); then
    c "${COLORS[high]}"
  elif ((pct >= 50)); then
    c "${COLORS[mid]}"
  else
    c "${COLORS[low]}"
  fi
}

cost_c() {
  local val="${1:-0}"
  local lo="${COST_THRESHOLDS[0]}" hi="${COST_THRESHOLDS[1]}"
  if awk "BEGIN { exit !($val >= $hi) }" 2>/dev/null; then
    c "${COLORS[high]}"
  elif awk "BEGIN { exit !($val >= $lo) }" 2>/dev/null; then
    c "${COLORS[mid]}"
  else
    c "${COLORS[low]}"
  fi
}

label() {
  local short="$1" long="$2"
  if [[ "$LABEL_STYLE" == "long" ]]; then
    printf '%s' "$long"
  else
    printf '%s' "$short"
  fi
}

# ── Config ────────────────────────────────────────────────────────────────────

load_config() {
  # Start with defaults
  SEGMENTS=("${DEFAULT_SEGMENTS[@]}")
  SEPARATOR="$DEFAULT_SEPARATOR"
  CACHE_TTL=$DEFAULT_CACHE_TTL
  GIT_CACHE_TTL=$DEFAULT_GIT_CACHE_TTL
  PATH_MAX_LENGTH=$DEFAULT_PATH_MAX_LENGTH
  SHOW_HOST="$DEFAULT_SHOW_HOST"
  GIT_BACKEND="$DEFAULT_GIT_BACKEND"
  LABEL_STYLE="$DEFAULT_LABEL_STYLE"
  COST_THRESHOLDS=("${DEFAULT_COST_THRESHOLDS[@]}")
  EXTRA_HIDE_ZERO=$DEFAULT_EXTRA_HIDE_ZERO
  CURRENCY="$DEFAULT_CURRENCY"
  for k in "${!DEFAULT_COLORS[@]}"; do
    COLORS[$k]="${DEFAULT_COLORS[$k]}"
  done

  # Overlay from config file if it exists
  if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    local cfg
    cfg=$(<"$CONFIG_FILE")

    # Segments
    local segs
    segs=$(echo "$cfg" | jq -r '.segments // empty | .[]' 2>/dev/null) || true
    if [[ -n "$segs" ]]; then
      SEGMENTS=()
      while IFS= read -r s; do SEGMENTS+=("$s"); done <<<"$segs"
    fi

    # Scalars
    local v
    v=$(echo "$cfg" | jq -r '.separator // empty' 2>/dev/null) && [[ -n "$v" ]] && SEPARATOR="$v"
    v=$(echo "$cfg" | jq -r '.cache_ttl // empty' 2>/dev/null) && [[ -n "$v" ]] && CACHE_TTL="$v"
    v=$(echo "$cfg" | jq -r '.git_cache_ttl // empty' 2>/dev/null) && [[ -n "$v" ]] && GIT_CACHE_TTL="$v"
    v=$(echo "$cfg" | jq -r '.path_max_length // empty' 2>/dev/null) && [[ -n "$v" ]] && PATH_MAX_LENGTH="$v"
    v=$(echo "$cfg" | jq -r '.show_host // empty' 2>/dev/null) && [[ -n "$v" ]] && SHOW_HOST="$v"
    v=$(echo "$cfg" | jq -r '.git_backend // empty' 2>/dev/null) && [[ -n "$v" ]] && GIT_BACKEND="$v"
    v=$(echo "$cfg" | jq -r '.label_style // empty' 2>/dev/null) && [[ -n "$v" ]] && LABEL_STYLE="$v"
    v=$(echo "$cfg" | jq -r '.extra_hide_zero // empty' 2>/dev/null) && [[ -n "$v" ]] && EXTRA_HIDE_ZERO="$v"
    v=$(echo "$cfg" | jq -r '.extra_only_burning // empty' 2>/dev/null) && [[ -n "$v" ]] && EXTRA_ONLY_BURNING="$v"
    v=$(echo "$cfg" | jq -r '.currency // empty' 2>/dev/null) && [[ -n "$v" ]] && CURRENCY="$v"
    local ct
    ct=$(echo "$cfg" | jq -r '.cost_thresholds // empty | .[]' 2>/dev/null) || true
    if [[ -n "$ct" ]]; then
      COST_THRESHOLDS=()
      while IFS= read -r t; do COST_THRESHOLDS+=("$t"); done <<<"$ct"
    fi

    # Colors
    local color_keys
    color_keys=$(echo "$cfg" | jq -r '.colors // {} | keys[]' 2>/dev/null) || true
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      v=$(echo "$cfg" | jq -r ".colors[\"$k\"] // empty" 2>/dev/null) || true
      [[ -n "$v" ]] && COLORS[$k]="$v"
    done <<<"$color_keys"
  fi

  mkdir -p "$CACHE_DIR"
}

# ── Utilities ─────────────────────────────────────────────────────────────────

shorten_path() {
  local full="$1" max="$2" project="${3:-}"
  local display=""

  # Replace home with ~
  full="${full/#$HOME/\~}"

  if [[ -n "$project" ]]; then
    local proj_short="${project/#$HOME/\~}"
    local proj_name="${proj_short##*/}"
    if [[ "$full" == "$proj_short"* ]]; then
      local rel="${full#"$proj_short"}"
      rel="${rel#/}"
      if [[ -z "$rel" ]]; then
        display="$proj_name"
      else
        # Abbreviate middle components
        local abbrev=""
        IFS='/' read -ra parts <<<"$rel"
        local last_idx=$((${#parts[@]} - 1))
        for i in "${!parts[@]}"; do
          if ((i == last_idx)); then
            abbrev+="${parts[$i]}"
          else
            abbrev+="${parts[$i]:0:1}/"
          fi
        done
        display="$proj_name/$abbrev"
      fi
    else
      display="$full"
    fi
  else
    display="$full"
  fi

  # Truncate from the left if too long
  if ((${#display} > max)); then
    display="…${display: -$((max - 1))}"
  fi

  printf '%s' "$display"
}

format_countdown() {
  local secs="$1"
  if ((secs <= 0)); then
    printf 'now'
    return
  fi
  local d h m
  d=$((secs / 86400))
  h=$(((secs % 86400) / 3600))
  m=$(((secs % 3600) / 60))
  if ((d > 0)); then
    printf '%dd%dh' "$d" "$h"
  elif ((h > 0)); then
    printf '%dh%02dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

secs_until_reset() {
  local iso="$1"
  [[ -z "$iso" || "$iso" == "null" ]] && {
    echo 0
    return
  }
  local target now
  if [[ "$PLATFORM" == "darwin" ]]; then
    target=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${iso%%.*}" +%s 2>/dev/null) || {
      echo 0
      return
    }
  else
    target=$(date -d "$iso" +%s 2>/dev/null) || {
      echo 0
      return
    }
  fi
  now=$(date +%s)
  echo $((target - now))
}

file_age() {
  local file="$1"
  [[ -f "$file" ]] || {
    echo 999999
    return
  }
  local mtime now
  if [[ "$PLATFORM" == "darwin" ]]; then
    mtime=$(stat -f %m "$file" 2>/dev/null) || {
      echo 999999
      return
    }
  else
    mtime=$(stat -c %Y "$file" 2>/dev/null) || {
      echo 999999
      return
    }
  fi
  now=$(date +%s)
  echo $((now - mtime))
}

# ── gitstatusd ────────────────────────────────────────────────────────────────

find_gitstatusd() {
  local arch
  arch=$(uname -m)
  local bin="$HOME/.cache/gitstatus/gitstatusd-${PLATFORM}-${arch}"
  [[ -x "$bin" ]] && {
    echo "$bin"
    return 0
  }
  return 1
}

query_gitstatusd() {
  local cwd="$1"
  local bin
  bin=$(find_gitstatusd) || return 1

  local branch="" staged=0 unstaged=0 untracked=0 ahead=0 behind=0

  # Spawn, query, kill using coproc
  coproc GITD { "$bin" --num-threads=2 2>/dev/null; }

  # Hello handshake
  printf '}\x1f\x1e' >&"${GITD[1]}" 2>/dev/null || {
    kill "$GITD_PID" 2>/dev/null
    wait "$GITD_PID" 2>/dev/null
    return 1
  }
  local hello
  IFS= read -r -d $'\x1e' -t 2 hello <&"${GITD[0]}" 2>/dev/null || {
    kill "$GITD_PID" 2>/dev/null
    wait "$GITD_PID" 2>/dev/null
    return 1
  }

  # Query
  printf '1 \x1f%s\x1f0\x1e' "$cwd" >&"${GITD[1]}" 2>/dev/null || {
    kill "$GITD_PID" 2>/dev/null
    wait "$GITD_PID" 2>/dev/null
    return 1
  }
  local resp
  IFS= read -r -d $'\x1e' -t 2 resp <&"${GITD[0]}" 2>/dev/null || {
    kill "$GITD_PID" 2>/dev/null
    wait "$GITD_PID" 2>/dev/null
    return 1
  }

  # Kill coproc
  kill "$GITD_PID" 2>/dev/null
  wait "$GITD_PID" 2>/dev/null

  # Parse \x1f-delimited fields
  IFS=$'\x1f' read -ra fields <<<"$resp"
  # Field indices per gitstatusd protocol
  # [2]=workdir [3]=commit [4]=branch [10]=staged [11]=unstaged [12]=conflicted [13]=untracked
  branch="${fields[4]:-}"
  staged="${fields[10]:-0}"
  unstaged="${fields[11]:-0}"
  local conflicted="${fields[12]:-0}"
  unstaged=$((unstaged + conflicted))
  untracked="${fields[13]:-0}"
  # Ahead/behind: fields[14]=commits_ahead [15]=commits_behind
  ahead="${fields[14]:-0}"
  behind="${fields[15]:-0}"

  printf '%s\t%s\t%s\t%s\t%s\t%s' "$branch" "$staged" "$unstaged" "$untracked" "$ahead" "$behind"
}

git_cli_query() {
  local cwd="$1"
  command -v git &>/dev/null || return 1

  local branch="" staged=0 unstaged=0 untracked=0 ahead=0 behind=0
  local output
  output=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null) || return 1

  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)
        branch="${line#\# branch.head }"
        if [[ "$branch" == "(detached)" ]]; then
          branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null) || branch="detached"
        fi
        ;;
      "# branch.ab "*)
        local ab="${line#\# branch.ab }"
        ahead="${ab%% *}"
        ahead="${ahead#+}"
        behind="${ab##* }"
        behind="${behind#-}"
        ;;
      1\ * | 2\ *)
        local xy="${line:2:2}"
        local x="${xy:0:1}" y="${xy:1:1}"
        [[ "$x" != "." ]] && ((staged++))
        [[ "$y" != "." ]] && ((unstaged++))
        ;;
      u\ *)
        ((unstaged++))
        ;;
      \?\ *)
        ((untracked++))
        ;;
    esac
  done <<<"$output"

  printf '%s\t%s\t%s\t%s\t%s\t%s' "$branch" "$staged" "$unstaged" "$untracked" "$ahead" "$behind"
}

get_primary_branch() {
  local cwd="$1"
  # Cache file is per-repo, keyed by the git toplevel path
  local toplevel
  toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 1
  local safe_key="${toplevel//\//_}"
  local cache_file="$CACHE_DIR/primary_branch${safe_key}"

  # Cache for 1 day (86400s)
  local age
  age=$(file_age "$cache_file")
  if ((age < 86400)) && [[ -s "$cache_file" ]]; then
    cat "$cache_file"
    return 0
  fi

  local primary=""
  # Try remote HEAD first
  primary=$(git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null) || true
  primary="${primary##refs/remotes/origin/}"

  # Fallback: check if main or master exists
  if [[ -z "$primary" ]]; then
    if git -C "$cwd" show-ref -q refs/heads/main 2>/dev/null; then
      primary="main"
    elif git -C "$cwd" show-ref -q refs/heads/master 2>/dev/null; then
      primary="master"
    fi
  fi

  [[ -z "$primary" ]] && return 1
  echo "$primary" >"$cache_file"
  echo "$primary"
}

get_git_status() {
  local cwd="$1"

  # Not a git repo? Skip
  git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null || return 1

  # Check cache freshness
  local age
  age=$(file_age "$GIT_CACHE")
  if ((age < GIT_CACHE_TTL)) && [[ -s "$GIT_CACHE" ]]; then
    cat "$GIT_CACHE"
    return 0
  fi

  local result=""

  # Try gitstatusd first (unless backend is "cli")
  if [[ "$GIT_BACKEND" != "cli" ]]; then
    result=$(query_gitstatusd "$cwd" 2>/dev/null) || true
  fi

  # Fallback to git CLI
  if [[ -z "$result" && "$GIT_BACKEND" != "daemon" ]]; then
    result=$(git_cli_query "$cwd" 2>/dev/null) || true
  fi

  # Write cache if we got a result
  if [[ -n "$result" ]]; then
    echo "$result" >"$GIT_CACHE"
    echo "$result"
    return 0
  fi

  # Use stale cache if available
  if [[ -s "$GIT_CACHE" ]]; then
    cat "$GIT_CACHE"
    return 0
  fi

  return 1
}

# ── API ───────────────────────────────────────────────────────────────────────

get_access_token() {
  local token=""
  if [[ "$PLATFORM" == "darwin" ]]; then
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
      jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null) || true
  else
    [[ -f "$CREDS_FILE" ]] || return 1
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS_FILE" 2>/dev/null) || true
  fi
  [[ -n "$token" ]] || return 1
  echo "$token"
}

fetch_usage() {
  local token
  token=$(get_access_token) || return 1

  # Check cache freshness
  local age
  age=$(file_age "$USAGE_CACHE")
  if ((age < CACHE_TTL)) && [[ -s "$USAGE_CACHE" ]]; then
    cat "$USAGE_CACHE"
    return 0
  fi

  # Fetch from API
  local resp http_code
  resp=$(curl -s -w '\n%{http_code}' --max-time 3 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || true

  http_code=$(echo "$resp" | tail -1)
  local body
  body=$(echo "$resp" | sed '$d')

  if [[ "$http_code" == "200" && -n "$body" ]]; then
    echo "$body" >"$USAGE_CACHE"
    echo "$body"
    return 0
  fi

  # Non-200: use stale cache if available
  if [[ -s "$USAGE_CACHE" ]]; then
    cat "$USAGE_CACHE"
    return 0
  fi

  return 1
}

# ── Stdin JSON Parsing ────────────────────────────────────────────────────────

read_stdin() {
  local input=""
  if [[ ! -t 0 ]]; then
    read -r input || true
  fi
  [[ -z "$input" ]] && return

  eval "$(echo "$input" | jq -r '
        @sh "MODEL=\(.data.model.display_name // .model.display_name // "")",
        @sh "CTX_PCT=\(.data.context_window.used_percentage // .context_window.used_percentage // "")",
        @sh "COST=\(.data.cost.total_cost_usd // .cost.total_cost_usd // "")",
        @sh "CWD=\(.workspace.current_dir // "")",
        @sh "PROJECT_DIR=\(.workspace.project_dir // "")"
    ' 2>/dev/null)" 2>/dev/null || true
}

# ── Segment Builders ─────────────────────────────────────────────────────────

seg_user() {
  local color
  if [[ "$USER" == "root" ]]; then
    color="${COLORS[user_root]}"
  else
    color="${COLORS[user]}"
  fi

  local display="$USER"

  # Show host if SSH or show_host=always
  if [[ "$SHOW_HOST" == "always" ]] || { [[ "$SHOW_HOST" == "auto" ]] && [[ -n "${SSH_CONNECTION:-}" ]]; }; then
    local host="${HOSTNAME:-$(hostname -s 2>/dev/null || echo '?')}"
    display+="$(c "${COLORS[mid]}")@${host}"
  fi

  printf '%b%s%b' "$(c "$color")" "$display" "$(c reset)"
}

seg_dir() {
  [[ -z "$CWD" ]] && return
  local shortened color
  shortened=$(shorten_path "$CWD" "$PATH_MAX_LENGTH" "$PROJECT_DIR")
  if [[ -n "$PROJECT_DIR" && "$CWD" != "$PROJECT_DIR" ]]; then
    color="${COLORS[mid]}"
  else
    color="${COLORS[dir]}"
  fi
  printf '%b%s%b' "$(c "$color")" "$shortened" "$(c reset)"
}

seg_git() {
  local cwd="${CWD:-$PWD}"
  [[ -z "$cwd" ]] && return

  local status_line
  status_line=$(get_git_status "$cwd") || return

  IFS=$'\t' read -r branch staged unstaged untracked ahead behind <<<"$status_line"
  [[ -z "$branch" ]] && return

  # Branch color: warning if on primary branch, clean if on a feature branch
  local primary_branch branch_color
  primary_branch=$(get_primary_branch "$cwd" 2>/dev/null) || primary_branch=""
  if [[ -n "$primary_branch" && "$branch" == "$primary_branch" ]]; then
    branch_color="${COLORS[git_branch_primary]}"
  else
    branch_color="${COLORS[git_branch_feature]}"
  fi

  local out=""
  out+="$(c "$branch_color")${branch}$(c reset)"

  # Indicators
  ((staged > 0)) && out+=" $(c "${COLORS[git_staged]}")+${staged}$(c reset)"
  ((unstaged > 0)) && out+=" $(c "${COLORS[git_unstaged]}")!${unstaged}$(c reset)"
  ((untracked > 0)) && out+=" $(c "${COLORS[git_untracked]}")?${untracked}$(c reset)"
  ((ahead > 0)) && out+=" $(c "${COLORS[git_ahead]}")⇡${ahead}$(c reset)"
  ((behind > 0)) && out+=" $(c "${COLORS[git_behind]}")⇣${behind}$(c reset)"

  printf '%s' "$out"
}

seg_model() {
  [[ -z "$MODEL" ]] && return
  printf '%b%s%b' "$(c "${COLORS[model]}")" "$MODEL" "$(c reset)"
}

seg_context() {
  local pct="${CTX_PCT:-0}"
  pct="${pct%%.*}"
  printf '%b%s %b%s%%%b' "$(c "${COLORS[label]}")" "$(label Ctx Context)" "$(usage_c "$pct")" "$pct" "$(c reset)"
}

seg_session() {
  local usage
  usage=$(fetch_usage 2>/dev/null) || return
  [[ -z "$usage" ]] && return

  local util resets_at
  util=$(echo "$usage" | jq -r '.five_hour.utilization // empty' 2>/dev/null) || return
  resets_at=$(echo "$usage" | jq -r '.five_hour.resets_at // empty' 2>/dev/null) || true
  [[ -z "$util" ]] && return

  local out=""
  out+="$(c "${COLORS[label]}")$(label Ses Session) $(c reset)"
  out+="$(usage_c "$util")${util}%$(c reset)"

  if [[ -n "$resets_at" && "$resets_at" != "null" ]]; then
    local secs
    secs=$(secs_until_reset "$resets_at")
    if ((secs > 0)); then
      out+=" $(c "${COLORS[reset_time]}")$(format_countdown "$secs")$(c reset)"
    fi
  fi

  printf '%s' "$out"
}

seg_weekly() {
  local usage
  usage=$(fetch_usage 2>/dev/null) || return
  [[ -z "$usage" ]] && return

  local util resets_at
  util=$(echo "$usage" | jq -r '.seven_day.utilization // empty' 2>/dev/null) || return
  resets_at=$(echo "$usage" | jq -r '.seven_day.resets_at // empty' 2>/dev/null) || true
  [[ -z "$util" ]] && return

  local out=""
  out+="$(c "${COLORS[label]}")$(label Wk Week) $(c reset)"
  out+="$(usage_c "$util")${util}%$(c reset)"

  if [[ -n "$resets_at" && "$resets_at" != "null" ]]; then
    local secs
    secs=$(secs_until_reset "$resets_at")
    if ((secs > 0)); then
      out+=" $(c "${COLORS[reset_time]}")$(format_countdown "$secs")$(c reset)"
    fi
  fi

  printf '%s' "$out"
}

seg_cost() {
  # Hide in subscription mode (have OAuth creds) — cost is only relevant for bedrock/API key
  get_access_token &>/dev/null && return
  local cost="${COST:-0}"
  local rounded
  rounded=$(printf '%.2f' "$cost" 2>/dev/null) || rounded="$cost"
  printf '%b%s %b%s%s%b' "$(c "${COLORS[label]}")" "$(label Cst Cost)" "$(cost_c "$cost")" "$CURRENCY" "$rounded" "$(c reset)"
}

seg_extra() {
  local usage
  usage=$(fetch_usage 2>/dev/null) || return
  [[ -z "$usage" ]] && return

  local enabled used limit
  enabled=$(echo "$usage" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null) || return
  [[ "$enabled" != "true" ]] && return

  used=$(echo "$usage" | jq -r '.extra_usage.used_credits // 0' 2>/dev/null) || true
  limit=$(echo "$usage" | jq -r '.extra_usage.monthly_limit // 0' 2>/dev/null) || true

  # Convert from cents to dollars
  local used_d limit_d
  used_d=$(awk "BEGIN { printf \"%.2f\", $used / 100 }" 2>/dev/null) || used_d="0.00"
  limit_d=$(awk "BEGIN { printf \"%.2f\", $limit / 100 }" 2>/dev/null) || limit_d="0.00"

  # Hide if zero and flag set
  if [[ "$EXTRA_HIDE_ZERO" == "true" && "$used_d" == "0.00" ]]; then
    return
  fi

  # Only show when actively burning extra (session or weekly at 100%)
  if [[ "$EXTRA_ONLY_BURNING" == "true" ]]; then
    local ses_util wk_util
    ses_util=$(echo "$usage" | jq -r '.five_hour.utilization // 0' 2>/dev/null) || ses_util=0
    wk_util=$(echo "$usage" | jq -r '.seven_day.utilization // 0' 2>/dev/null) || wk_util=0
    ses_util="${ses_util%%.*}"
    wk_util="${wk_util%%.*}"
    if ((ses_util < 100 && wk_util < 100)); then
      return
    fi
  fi

  local util
  util=$(echo "$usage" | jq -r '.extra_usage.utilization // 0' 2>/dev/null) || util=0
  local pct="${util%%.*}"

  printf '%b%s %b%s%s/%s%s%b' "$(c "${COLORS[label]}")" "$(label Ex Extra)" "$(usage_c "$pct")" "$CURRENCY" "$used_d" "$CURRENCY" "$limit_d" "$(c reset)"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  load_config
  read_stdin

  local parts=()
  for seg in "${SEGMENTS[@]}"; do
    local result
    result=$(seg_"$seg" 2>/dev/null) || true
    [[ -n "$result" ]] && parts+=("$result")
  done

  # Join with separator
  local sep output=""
  sep="$(c "${COLORS[separator]}")${SEPARATOR}$(c reset)"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    ((i > 0)) && output+="$sep"
    output+="${parts[i]}"
  done
  printf '%b' "$output"
}

main
