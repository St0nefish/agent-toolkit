# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

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
      if echo "$command" | perl -ne '$f=1,last if /^\s*pnpm\s+(list|--version|install|run|test|build)(\s|$)/; END{exit !$f}'; then
        allow "pnpm $(echo "$command" | awk '{print $2}') is allowed"
      fi
      return 0
      ;;
    yarn)
      if echo "$command" | perl -ne '$f=1,last if /^\s*yarn\s+(list|--version|install|run|test|build)(\s|$)/; END{exit !$f}'; then
        allow "yarn $(echo "$command" | awk '{print $2}') is allowed"
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
    build | ci | install | run | test)
      allow "npm $subcmd is a local build/test operation"
      ;;
    *)
      ask "npm $subcmd modifies packages or runs scripts"
      ;;
  esac
}
