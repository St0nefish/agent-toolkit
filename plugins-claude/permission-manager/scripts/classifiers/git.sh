# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

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

is_protected_branch() {
  local name="$1"
  name="${name#refs/heads/}"
  name="${name#origin/}"
  case "$name" in
    main | master) return 0 ;;
    *) return 1 ;;
  esac
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

# Check if git branch write operation targets a protected branch.
# Extracts positional args after write flags (-d, -m, etc.) to find branch names.
branch_targets_protected() {
  local -a args=("$@")
  local skip_next=false
  for arg in "${args[@]}"; do
    if [[ "$skip_next" == true ]]; then
      skip_next=false
      if is_protected_branch "$arg"; then return 0; fi
      continue
    fi
    case "$arg" in
      -d | -D | --delete | -m | -M | --move | -c | -C | --copy)
        skip_next=true
        ;;
      -*) ;;
      *)
        if is_protected_branch "$arg"; then return 0; fi
        ;;
    esac
  done
  return 1
}

# Check if checkout/switch is creating a new branch (-b/-B/-c/-C).
has_create_branch_flag() {
  local subcmd="$1"
  shift
  local -a args=("$@")
  case "$subcmd" in
    checkout)
      for arg in "${args[@]}"; do
        case "$arg" in -b | -B) return 0 ;; esac
      done
      ;;
    switch)
      for arg in "${args[@]}"; do
        case "$arg" in -c | -C | --create | --force-create) return 0 ;; esac
      done
      ;;
  esac
  return 1
}

# Extract the target branch name from checkout/switch args.
# For -b/-B/-c/-C, returns the name after the flag.
# Otherwise, returns the first positional argument.
extract_checkout_target() {
  local subcmd="$1"
  shift
  local -a args=("$@")
  local skip_next=false capture_next=false
  for arg in "${args[@]}"; do
    if [[ "$capture_next" == true ]]; then
      echo "$arg"
      return 0
    fi
    if [[ "$skip_next" == true ]]; then
      skip_next=false
      continue
    fi
    case "$arg" in
      -b | -B | -c | -C | --create | --force-create)
        capture_next=true
        ;;
      --track | -t | --orphan | --conflict | --pathspec-from-file)
        skip_next=true
        ;;
      --track=* | --conflict=* | --pathspec-from-file=*) ;;
      --detach | -d | --force | -f | --merge | -m | --quiet | -q | \
        --progress | --no-progress | --guess | --no-guess | \
        --recurse-submodules | --no-recurse-submodules | -l | --) ;;
      -*) ;;
      *)
        echo "$arg"
        return 0
        ;;
    esac
  done
}

# Classify git push: deny if targeting a protected branch.
check_git_push() {
  local -a args=("$@")
  local has_force=false

  for arg in "${args[@]}"; do
    case "$arg" in
      --force | -f | --force-with-lease | --force-if-includes) has_force=true ;;
    esac
  done

  # Extract positional args (remote, then refspecs)
  local -a positionals=()
  local skip_next=false
  for arg in "${args[@]}"; do
    if [[ "$skip_next" == true ]]; then
      skip_next=false
      continue
    fi
    case "$arg" in
      --repo | --receive-pack | --exec | -o | --push-option | --recurse-submodules)
        skip_next=true
        ;;
      -*) ;;
      *) positionals+=("$arg") ;;
    esac
  done

  # positionals[0] = remote, positionals[1+] = refspecs
  local i
  for ((i = 1; i < ${#positionals[@]}; i++)); do
    local refspec="${positionals[$i]}"
    local target
    if [[ "$refspec" == *":"* ]]; then
      target="${refspec#*:}"
    else
      target="$refspec"
    fi
    if is_protected_branch "$target"; then
      deny "git push to protected branch ($target) is not allowed"
      return 0
    fi
  done

  # Force push without explicit branch could target a protected branch
  if [[ "$has_force" == true && ${#positionals[@]} -le 1 ]]; then
    ask "git push --force without explicit branch (may target protected branch)"
    return 0
  fi

  allow "git push to non-protected branch"
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
      elif branch_targets_protected "${args[@]+"${args[@]}"}"; then
        deny "git branch write operation on protected branch (main/master)"
      else
        allow "git branch write operation on non-protected branch"
      fi
      ;;
    checkout | switch)
      local target
      target=$(extract_checkout_target "$subcmd" "${args[@]+"${args[@]}"}")
      if has_create_branch_flag "$subcmd" "${args[@]+"${args[@]}"}"; then
        if [[ -n "$target" ]] && is_protected_branch "$target"; then
          ask "Creating/resetting branch $target — confirm this is intentional"
        else
          allow "git $subcmd creates a new branch"
        fi
      elif [[ -n "$target" ]] && is_protected_branch "$target"; then
        allow "git $subcmd to protected branch (read-only switch)"
      else
        allow "git $subcmd to non-protected branch"
      fi
      ;;
    add)
      allow "git add stages files"
      ;;
    commit)
      allow "git commit to current branch"
      ;;
    push)
      check_git_push "${args[@]+"${args[@]}"}"
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
