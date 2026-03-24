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
    exec)
      # Skip exec-specific flags to extract container name and inner command
      local i=0
      while ((i < ${#args[@]})); do
        case "${args[i]}" in
          # Flags with arguments
          -u | --user | -w | --workdir | -e | --env | --env-file)
            ((i += 2))
            ;;
          # =form flags
          --user=* | --workdir=* | --env=* | --env-file=*)
            ((i += 1))
            ;;
          # Boolean flags
          -i | --interactive | -t | --tty | -d | --detach | --privileged)
            ((i += 1))
            ;;
          # Combined short flags (e.g. -it, -dit)
          -[itd][itd]*)
            ((i += 1))
            ;;
          *)
            break
            ;;
        esac
      done

      # args[i] is the container name, everything after is the inner command
      local container="${args[i]:-}"
      ((i += 1)) || true
      local inner_cmd="${args[*]:$i}"

      # No inner command (e.g. interactive shell) — ask
      if [[ -z "$inner_cmd" ]]; then
        ask "docker exec with no inner command (interactive shell)"
        return 0
      fi

      # Bare shell (bash, sh, zsh, etc.) with no arguments — interactive shell
      if [[ "$inner_cmd" =~ ^(bash|sh|zsh|ash|dash|fish|csh|tcsh|ksh)$ ]]; then
        ask "docker exec interactive shell ($inner_cmd)"
        return 0
      fi

      # Check redirections on the inner command
      check_redirections_ast "$inner_cmd"
      [[ "$CLASSIFY_MATCHED" -eq 1 ]] && return 0

      # Save/restore CLASSIFY_* globals around recursive classify
      local saved_result="$CLASSIFY_RESULT"
      local saved_reason="$CLASSIFY_REASON"
      local saved_matched="$CLASSIFY_MATCHED"

      local saved_explain="${EXPLAIN_LAST_CLASSIFIER:-}"
      if [[ -n "$saved_explain" ]]; then
        EXPLAIN_TRACE+=("INFO|check_docker|docker exec: classifying inner command: $inner_cmd")
        explain_classify_single_command "$inner_cmd"
      else
        classify_single_command "$inner_cmd"
      fi

      if [[ "$CLASSIFY_MATCHED" -eq 1 ]]; then
        CLASSIFY_REASON="docker exec inner command: $CLASSIFY_REASON"
        [[ -n "$saved_explain" ]] && EXPLAIN_LAST_CLASSIFIER="$saved_explain"
        return 0
      fi

      # Inner command unrecognized — restore and ask
      CLASSIFY_RESULT="$saved_result"
      CLASSIFY_REASON="$saved_reason"
      CLASSIFY_MATCHED="$saved_matched"
      [[ -n "$saved_explain" ]] && EXPLAIN_LAST_CLASSIFIER="check_docker"
      ask "docker exec with unrecognized inner command"
      ;;
    *)
      ask "docker $subcmd modifies container/image state"
      ;;
  esac
}
