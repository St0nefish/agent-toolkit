#!/usr/bin/env bash
# bash-safety.sh — PreToolUse hook for auto-approved Bash commands.
# Forces a user prompt (not hard-block) for:
#   1. Shell output redirection (> or >>) in any command
#   2. Destructive find operations (-delete, unsafe -exec/-execdir/-ok/-okdir)
#   3. Git write operations (commit, push, checkout, reset, etc.)
#   4. Gradle write operations (build, test, publish, etc.)
#
# Uses permissionDecision:"ask" so the user can still approve if intended.
# Uses permissionDecision:"allow" for read-only git/gradle ops (bypassing settings.json).

set -euo pipefail

HOOK_INPUT=$(cat)
# shellcheck source=scripts/hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0
command="$HOOK_COMMAND"
[[ -n "$command" ]] || exit 0

# Wrap hook_ask/hook_allow to also exit, as expected by callers.
ask()   { hook_ask "$1";   exit 0; }
allow() { hook_allow "$1"; exit 0; }

# --- Shell output redirection ---
# Catches > and >> but not fd duplication (2>&1, >&2) or process substitution >(...)
# Strip heredoc bodies first to avoid false positives on > inside string content
# (e.g., <noreply@anthropic.com> in Co-Authored-By lines)
check_redirection() {
  local stripped
  stripped=$(printf '%s' "$command" | perl -0777 -pe 's/<<[-~]?\\?\x27?(\w+)\x27?[^\n]*\n.*?\n\1(\n|$)/\n/gs')
  if echo "$stripped" | perl -ne '$f=1,last if /(?<![0-9&])>{1,2}(?![>&(])/; END{exit !$f}'; then
    ask "Command contains output redirection (> or >>)"
  fi
}

# --- Destructive find operations ---
check_find() {
  echo "$command" | perl -ne '$f=1,last if /^\s*find\s/; END{exit !$f}' || return 0

  # -delete is always destructive
  if echo "$command" | perl -ne '$f=1,last if /\s-delete\b/; END{exit !$f}'; then
    ask "find -delete can remove files"
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
      ask "find -exec with '$(echo "$unsafe" | head -1)' is not in the read-only safe list"
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

# --- Run checks in order ---
# Redirection and find checks run first (they may exit with "ask").
# Git/gradle checks run after — may exit with "allow" or "ask".
# If none match, fall through to exit 0 (no hook opinion).
check_redirection
check_find
check_git
check_gradle

exit 0
