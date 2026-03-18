# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Docker classifier ---

# Extract the Docker subcommand, skipping global flags.
# Sets REPLY to the subcommand and REPLY_ARGS to remaining tokens.
extract_docker_subcommand() {
  local -a tokens
  read -ra tokens <<<"$1"
  local i=1 len=${#tokens[@]}

  REPLY=""
  REPLY_ARGS=()

  while ((i < len)); do
    local token="${tokens[$i]}"
    case "$token" in
      # Global flags that take an argument
      --context | -c | --config | --host | -H | --log-level | -l | \
        --tlscacert | --tlscert | --tlskey)
        ((i += 2)) || true
        ;;
      --context=* | --config=* | --host=* | --log-level=* | \
        --tlscacert=* | --tlscert=* | --tlskey=*)
        ((i++)) || true
        ;;
      # Global boolean flags
      --debug | -D | --tls | --tlsverify)
        ((i++)) || true
        ;;
      -*)
        # Unknown global flag — skip
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

check_docker() {
  echo "$command" | perl -ne '$f=1,last if /^\s*docker(\s|$)/; END{exit !$f}' || return 0

  if ! extract_docker_subcommand "$command"; then
    if echo "$command" | perl -ne '$f=1,last if /\s--(version|help)\b/; END{exit !$f}'; then
      allow "docker --version/--help is read-only"
    fi
    return 0
  fi

  local subcmd="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")
  local subsubcmd="${args[0]:-}"

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
      # skip flags (and their arguments) to find the actual subcommand
      local compose_cmd=""
      local i=0
      while ((i < ${#args[@]})); do
        case "${args[i]}" in
          -f | --file | --env-file | -p | --project-name | --profile | --progress | --ansi)
            ((i += 2))
            ;; # skip flag + its argument
          --*=* | -*=*)
            ((i += 1))
            ;; # skip --flag=value
          -*)
            ((i += 1))
            ;; # skip unknown flag
          *)
            compose_cmd="${args[i]}"
            break
            ;;
        esac
      done
      case "$compose_cmd" in
        config | logs | ps | top | version) allow "docker compose $compose_cmd is read-only" ;;
        *) ask "docker compose $compose_cmd modifies container state" ;;
      esac
      ;;
    *)
      ask "docker $subcmd modifies container/image state"
      ;;
  esac
}
