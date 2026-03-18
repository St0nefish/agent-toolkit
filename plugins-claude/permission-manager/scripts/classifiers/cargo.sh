# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

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
    bench | build | clippy | clean | doc | fmt | test)
      allow "cargo $subcmd is a local build/test operation"
      ;;
    *)
      ask "cargo $subcmd modifies build state"
      ;;
  esac
}
