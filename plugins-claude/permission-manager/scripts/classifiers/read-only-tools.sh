# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Read-only tool fast-allow ---
check_read_only_tools() {
  local first_token
  first_token=$(echo "$command" | awk '{print $1}')

  case "$first_token" in
    # shell builtins (harmless navigation, environment, control flow)
    bash | sh | zsh | cd | export | set | source | type | true | false | hash | builtin | local | \
      declare | typeset | readonly | unset | return | shift | getopts | eval | trap | wait | \
      read | mapfile | readarray)
      allow "$first_token is a safe shell builtin"
      ;;

    # bash-read (output inspection, text processing, path/env utilities)
    cat | column | cut | diff | file | grep | head | jq | ls | md5sum | readlink | realpath | rg | \
      sha256sum | sha1sum | sort | stat | tail | test | tr | tree | uniq | wc | which | \
      basename | dirname | echo | printf | command | env)
      allow "$first_token is read-only"
      ;;

    # system (system state inspection)
    date | df | du | hostname | id | lsof | netstat | printenv | ps | pwd | ss | uname | uptime | whoami)
      allow "$first_token is read-only"
      ;;

    # top: only -bn1 (batch, non-interactive, single iteration)
    top)
      if echo "$command" | perl -ne '$f=1,last if /\s-bn1/; END{exit !$f}'; then
        allow "top -bn1 is read-only"
      fi
      ;;

    # tar: only read modes -tf / -tvf
    tar)
      if echo "$command" | perl -ne '$f=1,last if /\s-t[vf]/; END{exit !$f}'; then
        allow "tar read-only inspection"
      fi
      ;;

    # unzip: only -l (list) is read-only
    unzip)
      if echo "$command" | perl -ne '$f=1,last if /\s-[a-zA-Z]*l[a-zA-Z]*/; END{exit !$f}'; then
        allow "unzip -l is read-only"
      fi
      ;;

    # zip: only -sf (show files) is read-only
    zip)
      if echo "$command" | perl -ne '$f=1,last if /\s-[a-zA-Z]*sf[a-zA-Z]*/; END{exit !$f}'; then
        allow "zip -sf is read-only"
      fi
      ;;

    # xargs: allow only when invoking a known read-only command
    # Skip xargs flags (-0, -I, -n, -P, etc.) to find the actual subcommand.
    xargs)
      local -a xtokens
      read -ra xtokens <<<"$command"
      local xsub="" i=1
      while ((i < ${#xtokens[@]})); do
        local tok="${xtokens[$i]}"
        case "$tok" in
          -0 | -r | -x | -t | -p | -a | -E | -e | -L | -l | -s | -d | -P | -n | -I | -J | --*)
            # flags that consume a next argument
            case "$tok" in
              -I | -J | -n | -L | -l | -s | -d | -P | -a | -E | -e)
                ((i += 2)) || true ;;
              *)
                ((i++)) || true ;;
            esac
            ;;
          -*)
            ((i++)) || true ;;
          *)
            xsub="$tok"
            break
            ;;
        esac
      done
      if [[ -n "$xsub" ]]; then
        local xbase
        xbase=$(basename "$xsub")
        case "$xbase" in
          grep | egrep | fgrep | rg | cat | head | tail | less | more | file | stat | ls | wc | jq | \
            sort | uniq | cut | tr | diff | strings | xxd | od | hexdump | md5sum | sha256sum | sha1sum | \
            readlink | realpath | basename | dirname | echo | printf | test | \[)
            allow "xargs $xbase is read-only"
            ;;
        esac
      fi
      ;;
  esac
}
