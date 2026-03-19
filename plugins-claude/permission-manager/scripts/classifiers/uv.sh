# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- uv / Python package manager classifier ---

# Extract the uv subcommand, skipping global flags.
# Sets REPLY to the subcommand and REPLY_ARGS to remaining tokens.
extract_uv_subcommand() {
  local -a tokens
  read -ra tokens <<<"$1"
  local i=1 len=${#tokens[@]}

  REPLY=""
  REPLY_ARGS=()

  while ((i < len)); do
    local token="${tokens[$i]}"
    case "$token" in
      # Global flags that take an argument
      --color | --cache-dir | --python-preference | --directory | --project | \
        --config-file)
        ((i += 2)) || true
        ;;
      --color=* | --cache-dir=* | --python-preference=* | --directory=* | --project=* | \
        --config-file=*)
        ((i++)) || true
        ;;
      # Global boolean flags
      --no-cache | -n | --quiet | -q | --verbose | -v | --no-progress | --native-tls | \
        --no-native-tls | --offline | --no-offline | --no-config)
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

check_uv() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  # Handle uvx: just check --version/--help, otherwise passthrough
  case "$first_token" in
    uvx)
      if echo "$command" | perl -ne '$f=1,last if /^\s*uvx\s+(--version|--help)(\s|$)/; END{exit !$f}'; then
        allow "uvx $(echo "$command" | awk '{print $2}') is read-only"
      fi
      return 0
      ;;
    uv) ;;
    *) return 0 ;;
  esac

  if ! extract_uv_subcommand "$command"; then
    if echo "$command" | perl -ne '$f=1,last if /\s(-V|--version|--help)\b/; END{exit !$f}'; then
      allow "uv --version/--help is read-only"
    fi
    return 0
  fi

  local subcmd="$REPLY"
  local -a args=("${REPLY_ARGS[@]+"${REPLY_ARGS[@]}"}")
  local subsubcmd="${args[0]:-}"

  case "$subcmd" in
    version | --version | -V)
      allow "uv $subcmd is read-only"
      ;;
    tree | export | help)
      allow "uv $subcmd is read-only"
      ;;
    pip)
      case "$subsubcmd" in
        list | show | check | freeze)
          allow "uv pip $subsubcmd is read-only"
          ;;
        install | uninstall | compile | sync)
          allow "uv pip $subsubcmd is a local build operation"
          ;;
        *)
          ask "uv pip $subsubcmd modifies packages"
          ;;
      esac
      ;;
    python)
      case "$subsubcmd" in
        list | find | dir)
          allow "uv python $subsubcmd is read-only"
          ;;
        install | uninstall | pin)
          allow "uv python $subsubcmd is a local toolchain operation"
          ;;
        *)
          ask "uv python $subsubcmd modifies Python installations"
          ;;
      esac
      ;;
    tool)
      case "$subsubcmd" in
        list | dir)
          allow "uv tool $subsubcmd is read-only"
          ;;
        install | uninstall | upgrade)
          ask "uv tool $subsubcmd modifies global tool installations"
          ;;
        run)
          # uv tool run is an alias for uvx — executes arbitrary packages
          return 0
          ;;
        *)
          ask "uv tool $subsubcmd modifies tools"
          ;;
      esac
      ;;
    self)
      case "$subsubcmd" in
        version)
          allow "uv self version is read-only"
          ;;
        *)
          ask "uv self $subsubcmd modifies the uv installation"
          ;;
      esac
      ;;
    lock)
      # --check is read-only, otherwise it writes the lockfile
      if echo "$command" | perl -ne '$f=1,last if /\s--check(\s|$)/; END{exit !$f}'; then
        allow "uv lock --check is read-only"
      else
        allow "uv lock is a local build operation"
      fi
      ;;
    run)
      # uv run --with downloads and executes arbitrary packages (like uvx)
      if echo "$command" | perl -ne '$f=1,last if /\s--with(\s|=)/; END{exit !$f}'; then
        return 0
      fi
      allow "uv run is a local build/dev operation"
      ;;
    sync | add | remove | build | venv | init)
      allow "uv $subcmd is a local build/dev operation"
      ;;
    publish)
      ask "uv publish uploads to a package registry"
      ;;
    cache)
      case "$subsubcmd" in
        dir)
          allow "uv cache dir is read-only"
          ;;
        *)
          ask "uv cache $subsubcmd modifies the cache"
          ;;
      esac
      ;;
    *)
      ask "uv $subcmd modifies project state"
      ;;
  esac
}
