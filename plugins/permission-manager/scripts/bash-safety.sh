#!/usr/bin/env bash
# bash-safety.sh — PreToolUse hook for Bash command safety classification.
# Single authority for all Bash command permissions across Claude Code and Copilot CLI.
#
# Uses shfmt --tojson to parse compound commands into individual segments,
# then classifies each segment independently. The most restrictive result wins:
#   deny > ask > allow
#
# Classification buckets:
#   allow — read-only command; auto-approved on both CLIs.
#   ask   — write/modifying command; prompts user on Claude Code.
#           (Copilot CLI has no "ask" — falls through with no opinion.)
#   deny  — genuinely destructive pattern; hard-blocked everywhere.
#
# Classifiers cover:
#   bash-read / system — cat, grep, ls, ps, df, echo, printf, etc.
#   git               — read-only subcommands allow; write subcommands ask
#   gradle / jvm      — tasks/deps/properties allow; build/test/publish ask
#   github (gh)       — list/view/status allow; create/merge/edit ask
#   docker            — ps/logs/inspect allow; run/build/exec ask
#   npm / node        — list/audit/version allow; install/run/publish ask
#   pip / python      — list/show/freeze allow; install/uninstall ask
#   cargo / rust      — version/check/audit/metadata allow; build/test/run ask

set -euo pipefail

HOOK_INPUT=$(cat)
# shellcheck source=scripts/hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0
command="$HOOK_COMMAND"
[[ -n "$command" ]] || exit 0

# --- Bypass permissions mode ---
# When the user has opted into unrestricted execution, skip classification entirely.
# Claude Code: --dangerously-skip-permissions; Copilot CLI: --allow-all / --yolo
if [[ "$HOOK_PERMISSION_MODE" == "bypassPermissions" ]]; then
  exit 0
fi

# --- Dependency check ---
# shfmt and jq are hard requirements for compound command parsing.
# If missing, deny all Bash commands with a clear install message.
check_dependencies() {
  local missing=()
  command -v shfmt &>/dev/null || missing+=("shfmt")
  command -v jq &>/dev/null || missing+=("jq")
  if [[ ${#missing[@]} -gt 0 ]]; then
    hook_deny "bash-safety: missing required dependencies: ${missing[*]}. Run /permission-setup to install."
    exit 0
  fi
}

check_dependencies

# --- Custom command patterns ---
# Load user-defined allow-list globs from global and project config files.
# Patterns are matched per-segment via bash glob: [[ "$command" == $pattern ]]
# Override paths via env vars for testing:
#   COMMAND_PERMISSIONS_GLOBAL  — default: ~/.claude/command-permissions.json
#   COMMAND_PERMISSIONS_PROJECT — default: .claude/command-permissions.json
CUSTOM_ALLOW_PATTERNS=()

load_custom_patterns() {
  local global_file="${COMMAND_PERMISSIONS_GLOBAL:-${HOME}/.claude/command-permissions.json}"
  local project_file="${COMMAND_PERMISSIONS_PROJECT:-.claude/command-permissions.json}"
  for f in "$global_file" "$project_file"; do
    if [[ -f "$f" ]]; then
      local _p
      mapfile -t _p < <(jq -r '.allow[]? // empty' "$f" 2>/dev/null)
      CUSTOM_ALLOW_PATTERNS+=("${_p[@]+"${_p[@]}"}")
    fi
  done
}

load_custom_patterns

check_custom_patterns() {
  for pattern in "${CUSTOM_ALLOW_PATTERNS[@]+"${CUSTOM_ALLOW_PATTERNS[@]}"}"; do
    # shellcheck disable=SC2254
    if [[ "$command" == $pattern ]]; then
      allow "custom pattern: $pattern"
      return 0
    fi
  done
}

# --- Decision helpers ---
# In segment mode (SEGMENT_MODE=1), set globals and return.
# In direct mode (default), output JSON and exit.
SEGMENT_MODE=0
CLASSIFY_RESULT=0 # 0=allow, 1=ask, 2=deny
CLASSIFY_REASON=""
CLASSIFY_MATCHED=0 # 1 if any classifier made a decision

ask() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=1
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_ask "$1"
  exit 0
}

allow() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=0
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_allow "$1"
  exit 0
}

deny() {
  if [[ "$SEGMENT_MODE" -eq 1 ]]; then
    CLASSIFY_RESULT=2
    CLASSIFY_REASON="$1"
    CLASSIFY_MATCHED=1
    return 0
  fi
  hook_deny "$1"
  exit 0
}

# --- Compound command parsing via shfmt ---

# Extract all simple commands from a compound command string using shfmt's AST.
# Outputs one command per line.
parse_segments() {
  printf '%s' "$1" | shfmt --tojson 2>/dev/null | jq -r '
    def extract_cmds:
      if .Cmd?.Type? == "BinaryCmd" then
        (.Cmd.X | extract_cmds), (.Cmd.Y | extract_cmds)
      elif .Cmd?.Type? == "CallExpr" then
        [.Cmd.Args[]? | [.Parts[]? | select(.Type? == "Lit") | .Value] | join("")] | join(" ")
      elif type == "object" then
        if .Cmd? then .Cmd | extract_cmds else empty end
      else empty end;
    .Stmts[]? | extract_cmds
  ' 2>/dev/null
}

# Check for output redirections using shfmt AST.
# Must run on the FULL original command (before segment extraction),
# since parse_segments strips redirections from extracted segments.
check_redirections_ast() {
  local cmd="$1"
  local has_redir
  has_redir=$(printf '%s' "$cmd" | shfmt --tojson 2>/dev/null | jq '
    [.. | objects | select(.Redirs?) | .Redirs[]
     | select(.Op == 54 or .Op == 55)
     # Allow stderr redirects (N.Value == "2")
     | select((.N?.Value? // "") != "2")
     # Allow redirects to /dev/null (harmless output discard)
     | select(([.Word?.Parts[]? | select(.Type? == "Lit") | .Value] | join("")) != "/dev/null")
    ] | length
  ' 2>/dev/null || echo "0")
  # Op 54 = >, Op 55 = >>  (allow fd dup 59 = >&)
  # Excluded: stderr redirects (2>), and any redirect to /dev/null
  if [[ "$has_redir" -gt 0 ]]; then
    deny "Command contains output redirection (> or >>)"
  fi
}

# --- Destructive find operations ---
check_find() {
  echo "$command" | perl -ne '$f=1,last if /^\s*find\s/; END{exit !$f}' || return 0

  if echo "$command" | perl -ne '$f=1,last if /\s-delete\b/; END{exit !$f}'; then
    deny "find -delete can remove files"
    return 0
  fi

  if echo "$command" | perl -ne '$f=1,last if /\s-(exec|execdir|ok|okdir)\s/; END{exit !$f}'; then
    local unsafe
    unsafe=$(echo "$command" |
      perl -ne 'while (/-(exec|execdir|ok|okdir)\s+(\S+)/g) { print "$2\n" }' |
      while read -r cmd; do
        base=$(basename "$cmd" 2>/dev/null || echo "$cmd")
        case "$base" in
          grep | egrep | fgrep | rg | cat | head | tail | less | more | file | stat | ls | wc | jq | \
            sort | uniq | cut | tr | strings | xxd | od | hexdump | md5sum | sha256sum | sha1sum | \
            readlink | realpath | basename | dirname | test | \[) ;;
          *)
            echo "$base"
            ;;
        esac
      done)
    if [[ -n "$unsafe" ]]; then
      deny "find -exec with '$(echo "$unsafe" | head -1)' is not in the read-only safe list"
      return 0
    fi
  fi

  # find without dangerous flags is a read-only file search
  allow "find is read-only file search"
}

# --- Git command classifier ---

extract_git_subcommand() {
  local -a tokens
  read -ra tokens <<<"$1"
  local i=1 len=${#tokens[@]}

  REPLY=""
  REPLY_ARGS=()

  while ((i < len)); do
    local token="${tokens[$i]}"
    case "$token" in
      -C | -c | --git-dir | --work-tree | --namespace | --exec-path | --config-env | --super-prefix)
        ((i += 2)) || true
        ;;
      -C=* | --git-dir=* | --work-tree=* | --namespace=* | --exec-path=* | --config-env=* | --super-prefix=* | -c=*)
        ((i++)) || true
        ;;
      --no-pager | --bare | --no-replace-objects | --literal-pathspecs | \
        --no-optional-locks | --no-lazy-fetch | --paginate | -p | --glob-pathspecs | \
        --noglob-pathspecs | --icase-pathspecs | --no-advice)
        ((i++)) || true
        ;;
      -*)
        ((i++)) || true
        ;;
      *)
        REPLY="$token"
        ((i++)) || true
        if ((i <= len)); then
          REPLY_ARGS=("${tokens[@]:$i}")
        fi
        return 0
        ;;
    esac
  done

  return 1
}

is_readonly_branch() {
  local -a args=("$@")
  for arg in "${args[@]}"; do
    case "$arg" in
      -d | -D | -m | -M | -c | -C | --delete | --move | --copy | --edit-description | \
        --set-upstream-to | --set-upstream-to=* | -u | --unset-upstream | --track | --no-track)
        return 1
        ;;
    esac
  done
  return 0
}

is_readonly_stash() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    list | show) return 0 ;;
    *) return 1 ;;
  esac
}

is_readonly_tag() {
  local -a args=("$@")
  local has_list=false
  local has_write=false
  for arg in "${args[@]}"; do
    case "$arg" in
      -l | --list | --contains | --no-contains | --sort | --sort=* | --format | --format=* | \
        --merged | --no-merged | --points-at)
        has_list=true
        ;;
      -d | --delete | -a | -s | -f | --sign | --force | --create-reflog | -u | --local-user | --local-user=*)
        has_write=true
        ;;
    esac
  done
  if [[ "$has_write" == true ]]; then
    return 1
  fi
  if [[ "$has_list" == true ]]; then
    return 0
  fi
  if [[ ${#args[@]} -eq 0 ]]; then
    return 0
  fi
  return 1
}

is_readonly_remote() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    "" | -v | -vv) return 0 ;;
    show | get-url) return 0 ;;
    *) return 1 ;;
  esac
}

is_readonly_config() {
  local -a args=("$@")
  local has_read=false
  local has_write=false
  for arg in "${args[@]}"; do
    case "$arg" in
      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --show-origin | \
        --show-scope | --name-only | --type | --type=*)
        has_read=true
        ;;
      --set | --unset | --unset-all | --rename-section | --remove-section | --replace-all | \
        --add | --edit | -e)
        has_write=true
        ;;
    esac
  done
  if [[ "$has_write" == true ]]; then
    return 1
  fi
  if [[ "$has_read" == true ]]; then
    return 0
  fi
  return 1
}

is_readonly_worktree() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    list) return 0 ;;
    *) return 1 ;;
  esac
}

check_git() {
  echo "$command" | perl -ne '$f=1,last if /^\s*git(\s|$)/; END{exit !$f}' || return 0

  if ! extract_git_subcommand "$command"; then
    if echo "$command" | perl -ne '$f=1,last if /\s--(version|help)\b/; END{exit !$f}'; then
      allow "git --version/--help is read-only"
    fi
    return 0
  fi

  local subcmd="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")

  case "$subcmd" in
    log | diff | status | show | blame | shortlog | describe | rev-parse | rev-list | \
      ls-files | ls-tree | ls-remote | cat-file | reflog | for-each-ref | merge-base | \
      name-rev | count-objects | cherry | grep | version | help)
      allow "git $subcmd is read-only"
      ;;
    branch)
      if is_readonly_branch "${args[@]+"${args[@]}"}"; then
        allow "git branch (read-only invocation)"
      else
        ask "git branch with write flags"
      fi
      ;;
    stash)
      if is_readonly_stash "${args[@]+"${args[@]}"}"; then
        allow "git stash (read-only invocation)"
      else
        ask "git stash write operation"
      fi
      ;;
    tag)
      if is_readonly_tag "${args[@]+"${args[@]}"}"; then
        allow "git tag (read-only invocation)"
      else
        ask "git tag write operation"
      fi
      ;;
    remote)
      if is_readonly_remote "${args[@]+"${args[@]}"}"; then
        allow "git remote (read-only invocation)"
      else
        ask "git remote write operation"
      fi
      ;;
    config)
      if is_readonly_config "${args[@]+"${args[@]}"}"; then
        allow "git config (read-only invocation)"
      else
        ask "git config write operation"
      fi
      ;;
    worktree)
      if is_readonly_worktree "${args[@]+"${args[@]}"}"; then
        allow "git worktree (read-only invocation)"
      else
        ask "git worktree write operation"
      fi
      ;;
    *)
      ask "git $subcmd modifies repository state"
      ;;
  esac
}

# --- Gradle command classifier ---

extract_gradle_command() {
  local -a tokens
  read -ra tokens <<<"$1"
  local exe="${tokens[0]}"

  REPLY=""
  REPLY_ARGS=()

  case "$exe" in
    gradle | ./gradlew | gradlew)
      REPLY="$exe"
      if ((${#tokens[@]} > 1)); then
        REPLY_ARGS=("${tokens[@]:1}")
      fi
      return 0
      ;;
  esac
  return 1
}

extract_gradle_tasks() {
  local -a args=("$@")
  local i=0 len=${#args[@]}

  while ((i < len)); do
    local token="${args[$i]}"
    case "$token" in
      -p | -g | -b | -c | -I | -S | --project-dir | --gradle-user-home | --build-file | \
        --settings-file | --init-script | --console | --warning-mode | \
        --priority | --max-workers | --include-build | --project-cache-dir | \
        --configuration | --dependency | \
        -D* | -P*)
        case "$token" in
          -D*=* | -P*=*) ((i++)) || true ;;
          -D* | -P*) ((i++)) || true ;;
          *) ((i += 2)) || true ;;
        esac
        ;;
      --project-dir=* | --gradle-user-home=* | --build-file=* | --settings-file=* | \
        --init-script=* | --console=* | --warning-mode=* | --priority=* | \
        --max-workers=* | --include-build=* | --project-cache-dir=* | \
        --configuration=* | --dependency=*)
        ((i++)) || true
        ;;
      --version | --help | -h | -? | --no-daemon | --daemon | --foreground | --gui | \
        --info | -i | --debug | -d | --warn | -w | --quiet | -q | --stacktrace | -s | \
        --full-stacktrace | -S | --scan | --no-scan | --build-cache | --no-build-cache | \
        --configuration-cache | --no-configuration-cache | --configure-on-demand | \
        --no-configure-on-demand | --continue | --dry-run | -m | --no-parallel | \
        --parallel | --offline | --refresh-dependencies | --rerun-tasks | \
        --no-rebuild | --profile | --stop | --status | --continuous | -t | \
        --write-locks | --update-locks | --no-watch-fs | --watch-fs | \
        --export-keys | --no-search-upward | -u)
        ((i++)) || true
        ;;
      -*)
        ((i++)) || true
        ;;
      *)
        echo "$token"
        ((i++)) || true
        ;;
    esac
  done
}

is_readonly_gradle_task() {
  local task="$1"
  local bare="${task##*:}"
  case "$bare" in
    tasks | help | projects | properties | dependencies | dependencyInsight | \
      buildEnvironment | components | outgoingVariants | resolvableConfigurations | \
      javaToolchains | model)
      return 0
      ;;
  esac
  return 1
}

check_gradle() {
  echo "$command" | perl -ne '$f=1,last if /^\s*(\.?\/?)gradlew?(\s|$)/; END{exit !$f}' || return 0

  if ! extract_gradle_command "$command"; then
    return 0
  fi

  local exe="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")

  local has_version=false has_help=false has_dry_run=false
  for arg in "${args[@]+"${args[@]}"}"; do
    case "$arg" in
      --version) has_version=true ;;
      --help | -h | -\?) has_help=true ;;
      --dry-run | -m) has_dry_run=true ;;
    esac
  done

  if [[ "$has_version" == true ]]; then
    allow "gradle --version is read-only"
    return 0
  fi
  if [[ "$has_help" == true ]]; then
    allow "gradle --help is read-only"
    return 0
  fi

  local -a tasks=()
  while IFS= read -r task; do
    [[ -n "$task" ]] && tasks+=("$task")
  done < <(extract_gradle_tasks "${args[@]+"${args[@]}"}")

  if [[ ${#tasks[@]} -eq 0 ]]; then
    allow "bare gradle invocation is read-only"
    return 0
  fi

  if [[ "$has_dry_run" == true ]]; then
    allow "gradle --dry-run is read-only"
    return 0
  fi

  for task in "${tasks[@]}"; do
    if ! is_readonly_gradle_task "$task"; then
      ask "gradle $task modifies build state"
      return 0
    fi
  done

  allow "gradle tasks are all read-only reporting tasks"
}

# --- Read-only tool fast-allow ---
check_read_only_tools() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    # bash-read (output inspection, text processing, path/env utilities)
    cat | column | cut | diff | file | grep | head | jq | ls | md5sum | readlink | realpath | rg | \
      sha256sum | sha1sum | sort | stat | tail | test | tr | tree | uniq | wc | which | \
      basename | dirname | echo | printf | command | env)
      allow "$first_token is read-only"
      ;;

    # system (system state inspection)
    date | df | du | hostname | id | lsof | netstat | printenv | ps | pwd | ss | uname | uptime | whoami)
      allow "$first_token is read-only"
      ;;

    # top: only -bn1 (batch, non-interactive, single iteration)
    top)
      if echo "$command" | perl -ne '$f=1,last if /\s-bn1/; END{exit !$f}'; then
        allow "top -bn1 is read-only"
      fi
      ;;

    # tar: only read modes -tf / -tvf
    tar)
      if echo "$command" | perl -ne '$f=1,last if /\s-t[vf]/; END{exit !$f}'; then
        allow "tar read-only inspection"
      fi
      ;;

    # unzip: only -l (list) is read-only
    unzip)
      if echo "$command" | perl -ne '$f=1,last if /\s-[a-zA-Z]*l[a-zA-Z]*/; END{exit !$f}'; then
        allow "unzip -l is read-only"
      fi
      ;;

    # zip: only -sf (show files) is read-only
    zip)
      if echo "$command" | perl -ne '$f=1,last if /\s-[a-zA-Z]*sf[a-zA-Z]*/; END{exit !$f}'; then
        allow "zip -sf is read-only"
      fi
      ;;
  esac
}

# --- GitHub CLI classifier ---
check_gh() {
  echo "$command" | perl -ne '$f=1,last if /^\s*gh(\s|$)/; END{exit !$f}' || return 0

  local -a tokens
  read -ra tokens <<<"$command"

  local subcmd="${tokens[1]:-}"
  local subsubcmd="${tokens[2]:-}"

  case "$subcmd" in
    api)
      allow "gh api (read)"
      ;;
    auth)
      case "$subsubcmd" in
        status) allow "gh auth status is read-only" ;;
        *) ask "gh auth $subsubcmd modifies credentials" ;;
      esac
      ;;
    issue)
      case "$subsubcmd" in
        list | view | status) allow "gh issue $subsubcmd is read-only" ;;
        *) ask "gh issue $subsubcmd modifies issues" ;;
      esac
      ;;
    pr)
      case "$subsubcmd" in
        list | view | diff | checks | status) allow "gh pr $subsubcmd is read-only" ;;
        *) ask "gh pr $subsubcmd modifies pull requests" ;;
      esac
      ;;
    release)
      case "$subsubcmd" in
        list | view) allow "gh release $subsubcmd is read-only" ;;
        *) ask "gh release $subsubcmd modifies releases" ;;
      esac
      ;;
    repo)
      case "$subsubcmd" in
        view) allow "gh repo view is read-only" ;;
        *) ask "gh repo $subsubcmd modifies repositories" ;;
      esac
      ;;
    run)
      case "$subsubcmd" in
        list | view) allow "gh run $subsubcmd is read-only" ;;
        *) ask "gh run $subsubcmd modifies workflow runs" ;;
      esac
      ;;
    workflow)
      case "$subsubcmd" in
        list | view) allow "gh workflow $subsubcmd is read-only" ;;
        *) ask "gh workflow $subsubcmd modifies workflows" ;;
      esac
      ;;
    *)
      ask "gh $subcmd may modify GitHub resources"
      ;;
  esac
}

# --- Docker classifier ---
check_docker() {
  echo "$command" | perl -ne '$f=1,last if /^\s*docker(\s|$)/; END{exit !$f}' || return 0

  local -a tokens
  read -ra tokens <<<"$command"

  local subcmd="${tokens[1]:-}"
  local subsubcmd="${tokens[2]:-}"

  case "$subcmd" in
    --version) allow "docker --version is read-only" ;;
    images | inspect | logs | ps) allow "docker $subcmd is read-only" ;;
    stats)
      if echo "$command" | perl -ne '$f=1,last if /--no-stream/; END{exit !$f}'; then
        allow "docker stats --no-stream is read-only"
      fi
      ask "docker stats (interactive) requires user approval"
      ;;
    system)
      case "$subsubcmd" in
        df) allow "docker system df is read-only" ;;
        *) ask "docker system $subsubcmd modifies Docker state" ;;
      esac
      ;;
    network)
      case "$subsubcmd" in
        inspect | ls) allow "docker network $subsubcmd is read-only" ;;
        *) ask "docker network $subsubcmd modifies networks" ;;
      esac
      ;;
    volume)
      case "$subsubcmd" in
        inspect | ls) allow "docker volume $subsubcmd is read-only" ;;
        *) ask "docker volume $subsubcmd modifies volumes" ;;
      esac
      ;;
    compose)
      case "$subsubcmd" in
        config | logs | ps | top | version) allow "docker compose $subsubcmd is read-only" ;;
        *) ask "docker compose $subsubcmd modifies container state" ;;
      esac
      ;;
    *)
      ask "docker $subcmd modifies container/image state"
      ;;
  esac
}

# --- npm / Node.js package manager classifier ---
check_npm() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    node)
      if echo "$command" | perl -ne '$f=1,last if /^\s*node\s+(--version|-v)(\s|$)/; END{exit !$f}'; then
        allow "node --version is read-only"
      fi
      return 0
      ;;
    deno)
      if echo "$command" | perl -ne '$f=1,last if /^\s*deno\s+--version/; END{exit !$f}'; then
        allow "deno --version is read-only"
      fi
      return 0
      ;;
    npx)
      if echo "$command" | perl -ne '$f=1,last if /^\s*npx\s+--version/; END{exit !$f}'; then
        allow "npx --version is read-only"
      fi
      return 0
      ;;
    nvm)
      if echo "$command" | perl -ne '$f=1,last if /^\s*nvm\s+ls(\s|$)/; END{exit !$f}'; then
        allow "nvm ls is read-only"
      fi
      return 0
      ;;
    npm) ;;
    pnpm)
      if echo "$command" | perl -ne '$f=1,last if /^\s*pnpm\s+(list|--version)(\s|$)/; END{exit !$f}'; then
        allow "pnpm list/--version is read-only"
      fi
      return 0
      ;;
    yarn)
      if echo "$command" | perl -ne '$f=1,last if /^\s*yarn\s+(list|--version)(\s|$)/; END{exit !$f}'; then
        allow "yarn list/--version is read-only"
      fi
      return 0
      ;;
    *) return 0 ;;
  esac

  local -a tokens
  read -ra tokens <<<"$command"
  local subcmd="${tokens[1]:-}"

  case "$subcmd" in
    audit | list | ls | outdated | version | view | info | show | --version | -v)
      allow "npm $subcmd is read-only"
      ;;
    *)
      ask "npm $subcmd modifies packages or runs scripts"
      ;;
  esac
}

# --- pip / Python package manager classifier ---
check_pip() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    python | python3)
      if echo "$command" | perl -ne '$f=1,last if /^\s*python3?\s+--version/; END{exit !$f}'; then
        allow "$first_token --version is read-only"
      fi
      return 0
      ;;
    pipenv)
      if echo "$command" | perl -ne '$f=1,last if /^\s*pipenv\s+--version/; END{exit !$f}'; then
        allow "pipenv --version is read-only"
      fi
      return 0
      ;;
    poetry)
      if echo "$command" | perl -ne '$f=1,last if /^\s*poetry\s+(--version|show)(\s|$)/; END{exit !$f}'; then
        allow "poetry --version/show is read-only"
      fi
      ask "poetry $(echo "$command" | awk '{print $2}') modifies packages"
      ;;
    pyenv)
      if echo "$command" | perl -ne '$f=1,last if /^\s*pyenv\s+(versions|which)(\s|$)/; END{exit !$f}'; then
        allow "pyenv versions/which is read-only"
      fi
      return 0
      ;;
    uv)
      if echo "$command" | perl -ne '$f=1,last if /^\s*uv\s+(--version|pip\s+(list|show))(\s|$)/; END{exit !$f}'; then
        allow "uv --version/pip list/pip show is read-only"
      fi
      return 0
      ;;
    pip | pip3) ;;
    *) return 0 ;;
  esac

  local -a tokens
  read -ra tokens <<<"$command"
  local subcmd="${tokens[1]:-}"

  case "$subcmd" in
    check | freeze | list | show | --version | -V)
      allow "$first_token $subcmd is read-only"
      ;;
    *)
      ask "$first_token $subcmd modifies packages"
      ;;
  esac
}

# --- cargo / Rust toolchain classifier ---
check_cargo() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    rustc | rustup)
      if echo "$command" | perl -ne '$f=1,last if /^\s*rust[cu][p]?\s+(--version|-V|show)(\s|$)/; END{exit !$f}'; then
        allow "$first_token --version/show is read-only"
      fi
      return 0
      ;;
    cargo) ;;
    *) return 0 ;;
  esac

  local -a tokens
  read -ra tokens <<<"$command"
  local subcmd="${tokens[1]:-}"

  case "$subcmd" in
    --version | -V | audit | check | metadata | tree)
      allow "cargo $subcmd is read-only"
      ;;
    *)
      ask "cargo $subcmd modifies build state"
      ;;
  esac
}

# --- JVM tools classifier (java, javac, javap, kotlin, mvn) ---
check_jvm_tools() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    java)
      if echo "$command" | perl -ne '$f=1,last if /^\s*java\s+(-version|--version)/; END{exit !$f}'; then
        allow "java --version is read-only"
      fi
      return 0
      ;;
    javac)
      if echo "$command" | perl -ne '$f=1,last if /^\s*javac\s+(-version|--version)/; END{exit !$f}'; then
        allow "javac --version is read-only"
      fi
      return 0
      ;;
    javap)
      allow "javap is read-only"
      return 0
      ;;
    kotlin)
      if echo "$command" | perl -ne '$f=1,last if /^\s*kotlin\s+-version/; END{exit !$f}'; then
        allow "kotlin -version is read-only"
      fi
      return 0
      ;;
    mvn) ;;
    jar)
      if echo "$command" | perl -ne '$f=1,last if /^\s*jar\s+[- ]*t[vf]/; END{exit !$f}'; then
        allow "jar -tf/-tvf is read-only"
      fi
      return 0
      ;;
    *) return 0 ;;
  esac

  local -a tokens
  read -ra tokens <<<"$command"
  local subcmd="${tokens[1]:-}"

  case "$subcmd" in
    --version | -v)
      allow "mvn --version is read-only"
      ;;
    dependency:tree | help:effective-pom)
      allow "mvn $subcmd is read-only"
      ;;
    *)
      ask "mvn $subcmd modifies build state"
      ;;
  esac
}

# --- Classify a single command segment ---
# Sets CLASSIFY_RESULT (0=allow, 1=ask, 2=deny) and CLASSIFY_REASON.
classify_single_command() {
  local command="$1" # shadows the global for classifier reuse
  CLASSIFY_RESULT=0
  CLASSIFY_REASON=""
  CLASSIFY_MATCHED=0

  # Run classifiers — each may call allow/ask/deny which sets CLASSIFY_MATCHED
  check_custom_patterns
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_find
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_read_only_tools
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_git
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_gradle
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_gh
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_docker
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_npm
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_pip
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_cargo
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  check_jvm_tools
  [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

  # No classifier matched — unrecognized command
  CLASSIFY_RESULT=1
  CLASSIFY_REASON="Unrecognized command: $(echo "$command" | awk '{print $1}')"
  CLASSIFY_MATCHED=1
}

# --- Main entry ---
# Parse compound commands into segments, classify each, take most restrictive result.
main() {
  # Check redirections on the FULL original command before segmentation,
  # since parse_segments strips redirections from extracted segments.
  SEGMENT_MODE=1
  check_redirections_ast "$command"
  if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
    SEGMENT_MODE=0
    hook_deny "$CLASSIFY_REASON"
    exit 0
  fi

  local segments
  segments=$(parse_segments "$command")

  # If shfmt fails to parse (e.g. incomplete command), fall back to single-command mode
  if [[ -z "$segments" ]]; then
    segments="$command"
  fi

  local worst=0 worst_reason=""

  while IFS= read -r segment; do
    [[ -z "$segment" ]] && continue
    segment=$(echo "$segment" | sed 's/^ *//; s/ *$//')
    [[ -z "$segment" ]] && continue

    classify_single_command "$segment"
    if ((CLASSIFY_RESULT > worst)); then
      worst=$CLASSIFY_RESULT
      worst_reason="$CLASSIFY_REASON"
    elif [[ -z "$worst_reason" && -n "$CLASSIFY_REASON" ]]; then
      worst_reason="$CLASSIFY_REASON"
    fi
  done <<<"$segments"

  SEGMENT_MODE=0

  case $worst in
    0)
      hook_allow "$worst_reason"
      exit 0
      ;;
    1)
      if [[ "$HOOK_FORMAT" == "claude" ]]; then
        hook_ask "$worst_reason"
        exit 0
      fi
      # Copilot CLI: no ask equivalent — deny (user must run manually)
      hook_deny "$worst_reason"
      exit 0
      ;;
    2)
      hook_deny "$worst_reason"
      exit 0
      ;;
  esac
}

main
