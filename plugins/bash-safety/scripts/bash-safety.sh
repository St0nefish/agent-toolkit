#!/usr/bin/env bash
# bash-safety.sh — PreToolUse hook for auto-approved Bash commands.
# Classifies commands into three buckets:
#
#   allow — read-only command; auto-approved on both Claude Code and Copilot CLI.
#   ask   — write/modifying command; prompts user on Claude Code, hard-denied on Copilot CLI
#           (Copilot has no "ask" equivalent — user must run manually if intended).
#   deny  — genuinely destructive pattern (redirection, find -delete); hard-blocked everywhere.
#
# Classifiers cover the toolchains defined in permissions/*.json:
#   bash-read / system — cat, grep, ls, ps, df, etc.
#   git               — read-only subcommands allow; write subcommands ask
#   gradle / jvm      — tasks/deps/properties allow; build/test/publish ask; java/mvn versions allow
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

# Wrap hook_ask/hook_allow/hook_deny to also exit, as expected by callers.
ask()   { hook_ask "$1";   exit 0; }
allow() { hook_allow "$1"; exit 0; }
deny()  { hook_deny "$1";  exit 0; }

# --- Shell output redirection ---
# Catches > and >> but not fd duplication (2>&1, >&2) or process substitution >(...)
# Strip heredoc bodies first to avoid false positives on > inside string content
# (e.g., <noreply@anthropic.com> in Co-Authored-By lines)
check_redirection() {
  local stripped
  stripped=$(printf '%s' "$command" | perl -0777 -pe 's/<<[-~]?\\?\x27?(\w+)\x27?[^\n]*\n.*?\n\1(\n|$)/\n/gs')
  if echo "$stripped" | perl -ne '$f=1,last if /(?<![0-9&])>{1,2}(?![>&(])/; END{exit !$f}'; then
    deny "Command contains output redirection (> or >>)"
  fi
}

# --- Destructive find operations ---
check_find() {
  echo "$command" | perl -ne '$f=1,last if /^\s*find\s/; END{exit !$f}' || return 0

  # -delete is always destructive
  if echo "$command" | perl -ne '$f=1,last if /\s-delete\b/; END{exit !$f}'; then
    deny "find -delete can remove files"
  fi

  # -exec/-execdir/-ok/-okdir: allow known read-only commands, prompt for others
  if echo "$command" | perl -ne '$f=1,last if /\s-(exec|execdir|ok|okdir)\s/; END{exit !$f}'; then
    local unsafe
    unsafe=$(echo "$command" \
      | perl -ne 'while (/-(exec|execdir|ok|okdir)\s+(\S+)/g) { print "$2\n" }' \
      | while read -r cmd; do
          base=$(basename "$cmd" 2>/dev/null || echo "$cmd")
          case "$base" in
            grep|egrep|fgrep|rg|cat|head|tail|less|more|file|stat|ls|wc|jq|\
            sort|uniq|cut|tr|strings|xxd|od|hexdump|md5sum|sha256sum|sha1sum|\
            readlink|realpath|basename|dirname|test|\[)
              ;; # read-only, safe
            *)
              echo "$base"
              ;;
          esac
        done)
    if [[ -n "$unsafe" ]]; then
      deny "find -exec with '$(echo "$unsafe" | head -1)' is not in the read-only safe list"
    fi
  fi
}

# --- Git command classifier ---

# Extract the real git subcommand, parsing past global flags.
# Sets REPLY to the subcommand (e.g., "log", "commit", "push").
# Sets REPLY_ARGS to an array of remaining arguments after the subcommand.
# Returns 1 if no subcommand found (bare "git" or "git --version").
extract_git_subcommand() {
  local -a tokens
  read -ra tokens <<< "$1"
  local i=1 len=${#tokens[@]}  # start at 1 to skip "git"

  REPLY=""
  REPLY_ARGS=()

  while (( i < len )); do
    local token="${tokens[$i]}"
    case "$token" in
      # Flags that consume the next token as their argument
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)
        (( i += 2 )) || true
        ;;
      # Flags with = syntax (e.g., --git-dir=/path, -C=/path)
      -C=*|--git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--config-env=*|--super-prefix=*|-c=*)
        (( i++ )) || true
        ;;
      # Boolean global flags (no argument)
      --no-pager|--bare|--no-replace-objects|--literal-pathspecs|\
      --no-optional-locks|--no-lazy-fetch|--paginate|-p|--glob-pathspecs|\
      --noglob-pathspecs|--icase-pathspecs|--no-advice)
        (( i++ )) || true
        ;;
      # First non-flag token is the subcommand
      -*)
        # Unknown flag — treat as global flag, skip it
        (( i++ )) || true
        ;;
      *)
        REPLY="$token"
        (( i++ )) || true
        if (( i <= len )); then
          REPLY_ARGS=("${tokens[@]:$i}")
        fi
        return 0
        ;;
    esac
  done

  return 1
}

# Check if "git branch" invocation is read-only.
# Read-only: bare "git branch", --list, -a, -v, -vv, -r, --show-current,
#            --merged, --no-merged, --contains, --no-contains, --sort, --format
# Write: -d, -D, -m, -M, -c, -C, --delete, --move, --copy, --edit-description,
#        --set-upstream-to, -u, --unset-upstream, --track, --no-track
is_readonly_branch() {
  local -a args=("$@")
  for arg in "${args[@]}"; do
    case "$arg" in
      -d|-D|-m|-M|-c|-C|--delete|--move|--copy|--edit-description|\
      --set-upstream-to|--set-upstream-to=*|-u|--unset-upstream|--track|--no-track)
        return 1
        ;;
    esac
  done
  return 0
}

# Check if "git stash" invocation is read-only.
# Read-only: list, show
# Write: bare "git stash" (implicit push), pop, apply, drop, push, save, clear, create, store, branch
is_readonly_stash() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    list|show) return 0 ;;
    *) return 1 ;;  # bare "git stash" = implicit push, everything else is write
  esac
}

# Check if "git tag" invocation is read-only.
# Read-only: -l, --list, -v (verify), --verify, --contains, --no-contains, --sort, --format
# Write: -d, --delete, -a, -s, -f, --sign, --force, --create-reflog, or bare "git tag <name>"
is_readonly_tag() {
  local -a args=("$@")
  local has_list=false
  local has_write=false
  for arg in "${args[@]}"; do
    case "$arg" in
      -l|--list|--contains|--no-contains|--sort|--sort=*|--format|--format=*|\
      --merged|--no-merged|--points-at)
        has_list=true
        ;;
      -d|--delete|-a|-s|-f|--sign|--force|--create-reflog|-u|--local-user|--local-user=*)
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
  # Bare "git tag" with no flags = list tags
  if [[ ${#args[@]} -eq 0 ]]; then
    return 0
  fi
  # "git tag <name>" = create tag (write)
  return 1
}

# Check if "git remote" invocation is read-only.
# Read-only: bare "git remote", -v, show, get-url
# Write: add, remove, rm, rename, set-head, set-branches, set-url, prune, update
is_readonly_remote() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    ""|-v|-vv) return 0 ;;
    show|get-url) return 0 ;;
    *) return 1 ;;
  esac
}

# Check if "git config" invocation is read-only.
# Read-only: --get, --get-all, --get-regexp, --list, -l, --get-urlmatch, --show-origin, --show-scope
# Write: --set, --unset, --unset-all, --rename-section, --remove-section, --replace-all, --add, --edit, -e
is_readonly_config() {
  local -a args=("$@")
  local has_read=false
  local has_write=false
  for arg in "${args[@]}"; do
    case "$arg" in
      --get|--get-all|--get-regexp|--get-urlmatch|--list|-l|--show-origin|\
      --show-scope|--name-only|--type|--type=*)
        has_read=true
        ;;
      --set|--unset|--unset-all|--rename-section|--remove-section|--replace-all|\
      --add|--edit|-e)
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
  # Bare "git config key" without --get is ambiguous but typically a read in modern git.
  # However, "git config key value" is a write. To be safe, treat as write if no read flag.
  return 1
}

# Check if "git worktree" invocation is read-only.
is_readonly_worktree() {
  local -a args=("$@")
  local subcmd="${args[0]:-}"
  case "$subcmd" in
    list) return 0 ;;
    *) return 1 ;;
  esac
}

# Main git classifier. Extracts the subcommand and determines read-only vs write.
check_git() {
  # Only handle commands that start with "git"
  echo "$command" | perl -ne '$f=1,last if /^\s*git(\s|$)/; END{exit !$f}' || return 0

  # Extract the git portion — take everything up to && or || or ; or | for first command
  local git_cmd
  git_cmd=$(echo "$command" | sed 's/[;&|].*//')

  if ! extract_git_subcommand "$git_cmd"; then
    # Bare "git" with no subcommand, or git --version / git --help
    # Check if it's --version or --help
    if echo "$git_cmd" | perl -ne '$f=1,last if /\s--(version|help)\b/; END{exit !$f}'; then
      allow "git --version/--help is read-only"
    fi
    # Bare git with only flags — unusual, let it through
    return 0
  fi

  local subcmd="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")

  case "$subcmd" in
    # Simple read-only commands — always allow
    log|diff|status|show|blame|shortlog|describe|rev-parse|rev-list|\
    ls-files|ls-tree|ls-remote|cat-file|reflog|for-each-ref|merge-base|\
    name-rev|count-objects|cherry|grep|version|help)
      allow "git $subcmd is read-only"
      ;;

    # Dual-mode commands — inspect flags
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

    # Everything else is a write operation — ask
    *)
      ask "git $subcmd modifies repository state"
      ;;
  esac
}

# --- Gradle command classifier ---

# Extract the gradle executable and task/args from a command string.
# Sets REPLY to the gradle executable (gradle, ./gradlew, gradlew).
# Sets REPLY_ARGS to an array of all arguments after the executable.
# Returns 1 if the command is not a gradle invocation.
extract_gradle_command() {
  local -a tokens
  read -ra tokens <<< "$1"
  local exe="${tokens[0]}"

  REPLY=""
  REPLY_ARGS=()

  case "$exe" in
    gradle|./gradlew|gradlew)
      REPLY="$exe"
      if (( ${#tokens[@]} > 1 )); then
        REPLY_ARGS=("${tokens[@]:1}")
      fi
      return 0
      ;;
  esac
  return 1
}

# Extract gradle task names from args (skip flags and their values).
# Prints one task per line to stdout.
# Note: all arithmetic uses (( ... )) || true to avoid set -e killing the subshell
# when post-increment evaluates to 0.
extract_gradle_tasks() {
  local -a args=("$@")
  local i=0 len=${#args[@]}

  while (( i < len )); do
    local token="${args[$i]}"
    case "$token" in
      # Flags that consume the next token as their value
      -p|-g|-b|-c|-I|-S|--project-dir|--gradle-user-home|--build-file|\
      --settings-file|--init-script|--console|--warning-mode|\
      --priority|--max-workers|--include-build|--project-cache-dir|\
      --configuration|--dependency|\
      -D*|-P*)
        # -Dkey=val and -Pkey=val: if no = in token, might still be self-contained
        case "$token" in
          -D*=*|-P*=*) (( i++ )) || true ;;  # self-contained, skip one
          -D*|-P*)     (( i++ )) || true ;;  # self-contained (e.g., -Dfoo)
          *)           (( i += 2 )) || true ;;  # flag + next token
        esac
        ;;
      # Flags with = syntax
      --project-dir=*|--gradle-user-home=*|--build-file=*|--settings-file=*|\
      --init-script=*|--console=*|--warning-mode=*|--priority=*|\
      --max-workers=*|--include-build=*|--project-cache-dir=*|\
      --configuration=*|--dependency=*)
        (( i++ )) || true
        ;;
      # Boolean flags (no value)
      --version|--help|-h|-?|--no-daemon|--daemon|--foreground|--gui|\
      --info|-i|--debug|-d|--warn|-w|--quiet|-q|--stacktrace|-s|\
      --full-stacktrace|-S|--scan|--no-scan|--build-cache|--no-build-cache|\
      --configuration-cache|--no-configuration-cache|--configure-on-demand|\
      --no-configure-on-demand|--continue|--dry-run|-m|--no-parallel|\
      --parallel|--offline|--refresh-dependencies|--rerun-tasks|\
      --no-rebuild|--profile|--stop|--status|--continuous|-t|\
      --write-locks|--update-locks|--no-watch-fs|--watch-fs|\
      --export-keys|--no-search-upward|-u)
        (( i++ )) || true
        ;;
      # Anything starting with - that we didn't match — skip it
      -*)
        (( i++ )) || true
        ;;
      # Non-flag token = task name (may include project prefix like :sub:task)
      *)
        echo "$token"
        (( i++ )) || true
        ;;
    esac
  done
}

# Read-only gradle tasks — reporting/inspection only, no side effects.
is_readonly_gradle_task() {
  local task="$1"
  # Strip project prefix (e.g., :subproject:tasks → tasks)
  local bare="${task##*:}"
  case "$bare" in
    tasks|help|projects|properties|dependencies|dependencyInsight|\
    buildEnvironment|components|outgoingVariants|resolvableConfigurations|\
    javaToolchains|model)
      return 0
      ;;
  esac
  return 1
}

# Main gradle classifier.
check_gradle() {
  # Match commands starting with gradle, ./gradlew, or gradlew
  echo "$command" | perl -ne '$f=1,last if /^\s*(\.?\/?)gradlew?(\s|$)/; END{exit !$f}' || return 0

  # Extract the gradle portion — take everything up to && or || or ; or |
  local gradle_cmd
  gradle_cmd=$(echo "$command" | sed 's/[;&|].*//')

  if ! extract_gradle_command "$gradle_cmd"; then
    return 0
  fi

  local exe="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")

  # --version and --help with no tasks are always read-only
  local has_version=false has_help=false has_dry_run=false
  for arg in "${args[@]+"${args[@]}"}"; do
    case "$arg" in
      --version) has_version=true ;;
      --help|-h|-\?) has_help=true ;;
      --dry-run|-m) has_dry_run=true ;;
    esac
  done

  if [[ "$has_version" == true ]]; then
    allow "gradle --version is read-only"
  fi
  if [[ "$has_help" == true ]]; then
    allow "gradle --help is read-only"
  fi

  # Extract task names
  local -a tasks=()
  while IFS= read -r task; do
    [[ -n "$task" ]] && tasks+=("$task")
  done < <(extract_gradle_tasks "${args[@]+"${args[@]}"}")

  # No tasks = bare "gradle" — read-only (shows help)
  if [[ ${#tasks[@]} -eq 0 ]]; then
    allow "bare gradle invocation is read-only"
  fi

  # --dry-run/-m makes any task read-only
  if [[ "$has_dry_run" == true ]]; then
    allow "gradle --dry-run is read-only"
  fi

  # Check if ALL tasks are read-only
  for task in "${tasks[@]}"; do
    if ! is_readonly_gradle_task "$task"; then
      ask "gradle $task modifies build state"
    fi
  done

  # All tasks are read-only
  allow "gradle tasks are all read-only reporting tasks"
}

# --- Read-only tool fast-allow ---
# Commands whose first token is inherently read-only (from permissions/bash-read.json and
# permissions/system.json). These have no write modes in normal use.
# Special-cased partial commands (tar, unzip, zip) are handled separately.
check_read_only_tools() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    # bash-read.json (output inspection, text processing)
    cat|column|cut|diff|file|grep|head|jq|ls|md5sum|readlink|realpath|rg|\
    sha256sum|sha1sum|sort|stat|tail|test|tr|tree|uniq|wc|which)
      allow "$first_token is read-only"
      ;;

    # system.json (system state inspection)
    date|df|du|hostname|id|lsof|netstat|printenv|ps|pwd|ss|uname|uptime|whoami)
      allow "$first_token is read-only"
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

  local gh_cmd
  gh_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$gh_cmd"

  local subcmd="${tokens[1]:-}"
  local subsubcmd="${tokens[2]:-}"

  case "$subcmd" in
    api)
      # gh api is a read by convention (GET), trust user on this one
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
        list|view|status) allow "gh issue $subsubcmd is read-only" ;;
        *) ask "gh issue $subsubcmd modifies issues" ;;
      esac
      ;;
    pr)
      case "$subsubcmd" in
        list|view|diff|checks|status) allow "gh pr $subsubcmd is read-only" ;;
        *) ask "gh pr $subsubcmd modifies pull requests" ;;
      esac
      ;;
    release)
      case "$subsubcmd" in
        list|view) allow "gh release $subsubcmd is read-only" ;;
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
        list|view) allow "gh run $subsubcmd is read-only" ;;
        *) ask "gh run $subsubcmd modifies workflow runs" ;;
      esac
      ;;
    workflow)
      case "$subsubcmd" in
        list|view) allow "gh workflow $subsubcmd is read-only" ;;
        *) ask "gh workflow $subsubcmd modifies workflows" ;;
      esac
      ;;
    *)
      # Unknown gh subcommand — ask
      ask "gh $subcmd may modify GitHub resources"
      ;;
  esac
}

# --- Docker classifier ---
check_docker() {
  echo "$command" | perl -ne '$f=1,last if /^\s*docker(\s|$)/; END{exit !$f}' || return 0

  local docker_cmd
  docker_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$docker_cmd"

  local subcmd="${tokens[1]:-}"
  local subsubcmd="${tokens[2]:-}"

  case "$subcmd" in
    --version) allow "docker --version is read-only" ;;
    images|inspect|logs|ps) allow "docker $subcmd is read-only" ;;
    stats)
      # Only allow --no-stream (non-interactive)
      if echo "$docker_cmd" | perl -ne '$f=1,last if /--no-stream/; END{exit !$f}'; then
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
        inspect|ls) allow "docker network $subsubcmd is read-only" ;;
        *) ask "docker network $subsubcmd modifies networks" ;;
      esac
      ;;
    volume)
      case "$subsubcmd" in
        inspect|ls) allow "docker volume $subsubcmd is read-only" ;;
        *) ask "docker volume $subsubcmd modifies volumes" ;;
      esac
      ;;
    compose)
      case "$subsubcmd" in
        config|logs|ps|top|version) allow "docker compose $subsubcmd is read-only" ;;
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
      # node --version is read-only; node <script> is execution
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
    npm)
      ;;
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
    *)
      return 0
      ;;
  esac

  # npm subcommand classifier
  local npm_cmd subcmd
  npm_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$npm_cmd"
  subcmd="${tokens[1]:-}"

  case "$subcmd" in
    audit|list|ls|outdated|version|view|info|show|--version|-v)
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
    python|python3)
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
    pip|pip3)
      ;;
    *)
      return 0
      ;;
  esac

  # pip/pip3 subcommand classifier
  local pip_cmd subcmd
  pip_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$pip_cmd"
  subcmd="${tokens[1]:-}"

  case "$subcmd" in
    check|freeze|list|show|--version|-V)
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
    rustc|rustup)
      if echo "$command" | perl -ne '$f=1,last if /^\s*rust[cu][p]?\s+(--version|-V|show)(\s|$)/; END{exit !$f}'; then
        allow "$first_token --version/show is read-only"
      fi
      return 0
      ;;
    cargo)
      ;;
    *)
      return 0
      ;;
  esac

  local cargo_cmd subcmd
  cargo_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$cargo_cmd"
  subcmd="${tokens[1]:-}"

  case "$subcmd" in
    --version|-V|audit|check|metadata|tree)
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
      ;;
    kotlin)
      if echo "$command" | perl -ne '$f=1,last if /^\s*kotlin\s+-version/; END{exit !$f}'; then
        allow "kotlin -version is read-only"
      fi
      return 0
      ;;
    mvn)
      ;;
    jar)
      # Only allow -tf / -tvf (list contents)
      if echo "$command" | perl -ne '$f=1,last if /^\s*jar\s+[- ]*t[vf]/; END{exit !$f}'; then
        allow "jar -tf/-tvf is read-only"
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac

  # mvn subcommand classifier
  local mvn_cmd subcmd
  mvn_cmd=$(echo "$command" | sed 's/[;&|].*//')
  local -a tokens
  read -ra tokens <<< "$mvn_cmd"
  subcmd="${tokens[1]:-}"

  case "$subcmd" in
    --version|-v)
      allow "mvn --version is read-only"
      ;;
    dependency:tree|help:effective-pom)
      allow "mvn $subcmd is read-only"
      ;;
    *)
      ask "mvn $subcmd modifies build state"
      ;;
  esac
}

# --- Run checks in order ---
# Redirection and find checks run first (they may exit with "deny").
# Read-only tool fast-allow runs next.
# Tool-specific classifiers run after — may exit with "allow" or "ask".
# If none match, fall through to exit 0 (no hook opinion).
check_redirection
check_find
check_read_only_tools
check_git
check_gradle
check_gh
check_docker
check_npm
check_pip
check_cargo
check_jvm_tools

exit 0
