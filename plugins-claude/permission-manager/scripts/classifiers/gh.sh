# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

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
