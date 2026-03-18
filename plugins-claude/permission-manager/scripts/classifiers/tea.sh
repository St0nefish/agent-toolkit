# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Gitea CLI (tea) classifier ---
check_tea() {
  echo "$command" | perl -ne '$f=1,last if /^\s*tea(\s|$)/; END{exit !$f}' || return 0

  local -a tokens
  read -ra tokens <<<"$command"

  local subcmd="${tokens[1]:-}"
  local subsubcmd="${tokens[2]:-}"

  case "$subcmd" in
    api)
      allow "tea api (read)"
      ;;
    whoami)
      allow "tea whoami is read-only"
      ;;
    issues | issue | i)
      case "$subsubcmd" in
        "" | list | ls | view) allow "tea issues $subsubcmd is read-only" ;;
        create | c | edit | e | reopen | open | close) ask "tea issues $subsubcmd modifies issues" ;;
        *) [[ "$subsubcmd" =~ ^[0-9]+$ ]] && allow "tea issues view by index" || ask "tea issues $subsubcmd modifies issues" ;;
      esac
      ;;
    pulls | pull | pr)
      case "$subsubcmd" in
        "" | list | ls | view | checkout | co) allow "tea pulls $subsubcmd is read-only" ;;
        create | c | close | reopen | open | review | clean) ask "tea pulls $subsubcmd modifies pull requests" ;;
        *) [[ "$subsubcmd" =~ ^[0-9]+$ ]] && allow "tea pulls view by index" || ask "tea pulls $subsubcmd modifies pull requests" ;;
      esac
      ;;
    releases | release | r)
      case "$subsubcmd" in
        "" | list | ls | view) allow "tea releases $subsubcmd is read-only" ;;
        create | c | edit | e | delete | d) ask "tea releases $subsubcmd modifies releases" ;;
        *) [[ "$subsubcmd" =~ ^[0-9]+$ ]] && allow "tea releases view by index" || ask "tea releases $subsubcmd modifies releases" ;;
      esac
      ;;
    repos | repo)
      case "$subsubcmd" in
        "" | list | ls | search | s) allow "tea repos $subsubcmd is read-only" ;;
        *) ask "tea repos $subsubcmd modifies repositories" ;;
      esac
      ;;
    branches | branch | b)
      case "$subsubcmd" in
        "" | list | ls) allow "tea branches $subsubcmd is read-only" ;;
        *) ask "tea branches $subsubcmd modifies branches" ;;
      esac
      ;;
    labels | label)
      case "$subsubcmd" in
        "" | list | ls) allow "tea labels $subsubcmd is read-only" ;;
        *) ask "tea labels $subsubcmd modifies labels" ;;
      esac
      ;;
    milestones | milestone | ms)
      case "$subsubcmd" in
        "" | list | ls) allow "tea milestones $subsubcmd is read-only" ;;
        *) ask "tea milestones $subsubcmd modifies milestones" ;;
      esac
      ;;
    times | time | t)
      case "$subsubcmd" in
        "" | list | ls) allow "tea times $subsubcmd is read-only" ;;
        *) ask "tea times $subsubcmd modifies tracked times" ;;
      esac
      ;;
    notifications | notification | n)
      case "$subsubcmd" in
        "" | list | ls) allow "tea notifications $subsubcmd is read-only" ;;
        *) ask "tea notifications $subsubcmd modifies notification state" ;;
      esac
      ;;
    actions | action)
      ask "tea actions $subsubcmd modifies repository actions"
      ;;
    organizations | organization | org)
      case "$subsubcmd" in
        "" | list | ls) allow "tea organizations $subsubcmd is read-only" ;;
        *) ask "tea organizations $subsubcmd modifies organizations" ;;
      esac
      ;;
    logins | login)
      ask "tea login modifies credentials"
      ;;
    logout)
      ask "tea logout modifies credentials"
      ;;
    open | o)
      allow "tea open is read-only (opens browser)"
      ;;
    clone | C)
      allow "tea clone is a local operation"
      ;;
    comment | c)
      ask "tea comment modifies issues/PRs"
      ;;
    webhooks | webhook | hooks | hook)
      ask "tea webhooks $subsubcmd modifies webhooks"
      ;;
    admin | a)
      ask "tea admin requires elevated access"
      ;;
    help | h | --help | -h | --version | -v)
      allow "tea $subcmd is read-only"
      ;;
    *)
      ask "tea $subcmd may modify Gitea resources"
      ;;
  esac
}
