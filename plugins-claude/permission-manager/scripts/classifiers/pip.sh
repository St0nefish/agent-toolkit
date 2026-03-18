# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

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
      if echo "$command" | perl -ne '$f=1,last if /^\s*poetry\s+(--version|show|install|run|build|check|lock)(\s|$)/; END{exit !$f}'; then
        allow "poetry $(echo "$command" | awk '{print $2}') is allowed"
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
      if echo "$command" | perl -ne '$f=1,last if /^\s*uv\s+(--version|pip\s+(list|show|install)|run|sync|lock|build)(\s|$)/; END{exit !$f}'; then
        allow "uv $(echo "$command" | awk '{print $2}') is allowed"
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
    install)
      allow "$first_token install is a local build operation"
      ;;
    *)
      ask "$first_token $subcmd modifies packages"
      ;;
  esac
}
