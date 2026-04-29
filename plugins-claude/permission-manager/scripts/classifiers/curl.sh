# shellcheck shell=bash
# shellcheck source=../lib-classify.sh
# shellcheck source=../lib-web-domains.sh

# --- curl classifier ---
# Treats curl as read-only by default and asks when flags indicate a
# state-changing request (POST/PUT/etc.), data/file upload, or a write
# to local disk outside of /tmp//dev/null.
#
# When web-permissions is in "domains" mode, also restricts read-only curl
# to URLs whose host matches the WebFetch allow-list. This unifies curl with
# the WebFetch domain config — no need to maintain two lists.
#
# Mode behavior (after dangerous-flag screening):
#   off     — allow read-only curl to any URL (no domain check)
#   all     — allow read-only curl to any URL
#   domains — every URL token in the command must match WEB_DOMAINS, else ask
check_curl() {
  echo "$command" | perl -ne '$f=1,last if /^\s*curl(\s|$)/; END{exit !$f}' || return 0

  local -a tokens=() urls=()
  read -ra tokens <<<"$command"

  local i=1 len=${#tokens[@]}
  local tok letters method target

  while ((i < len)); do
    tok="${tokens[$i]}"
    case "$tok" in
      # === Mutating / write flags → ask ===
      --data | --data-ascii | --data-binary | --data-raw | --data-urlencode | \
        --data=* | --data-ascii=* | --data-binary=* | --data-raw=* | --data-urlencode=* | \
        --form | --form=* | --form-string | --form-string=* | \
        --upload-file | --upload-file=* | \
        --cookie-jar | --cookie-jar=* | \
        --config | --config=* | \
        --remote-name | --remote-name-all | --remote-header-name | --create-dirs | \
        -O)
        ask "curl ${tok%%=*} sends body / uploads / writes disk"
        return 0
        ;;

      # Output to file — allow scratch destinations (/tmp/, /dev/null)
      -o | --output)
        target="${tokens[$((i + 1))]:-}"
        if [[ "$target" == "/dev/null" || "$target" == /tmp/* ]]; then
          ((i += 2)) || true
          continue
        fi
        ask "curl writes to local file: $target"
        return 0
        ;;
      --output=*)
        target="${tok#*=}"
        if [[ "$target" == "/dev/null" || "$target" == /tmp/* ]]; then
          ((i++)) || true
          continue
        fi
        ask "curl writes to local file: $target"
        return 0
        ;;

      # -X / --request — only GET/HEAD allowed
      -X | --request)
        method="${tokens[$((i + 1))]:-}"
        case "$method" in
          GET | HEAD | get | head | "")
            ((i += 2)) || true
            ;;
          *)
            ask "curl -X $method (mutating method)"
            return 0
            ;;
        esac
        ;;
      -X=* | --request=*)
        method="${tok#*=}"
        case "$method" in
          GET | HEAD | get | head)
            ((i++)) || true
            ;;
          *)
            ask "curl -X $method (mutating method)"
            return 0
            ;;
        esac
        ;;
      -X[A-Za-z]*)
        method="${tok#-X}"
        case "$method" in
          GET | HEAD | get | head)
            ((i++)) || true
            ;;
          *)
            ask "curl -X$method (mutating method)"
            return 0
            ;;
        esac
        ;;

      # === Flags whose next token is an argument value (not a URL) ===
      # Skip these to avoid treating their values as fetch URLs (e.g. --referer
      # https://x.com is the Referer header, not a request target).
      -e | --referer | -x | --proxy | --proxy-user | --proxy-header | \
        -H | --header | -A | --user-agent | -u | --user | -b | --cookie | \
        -w | --write-out | -m | --max-time | --connect-timeout | \
        --retry | --retry-delay | --retry-max-time | --retry-connrefused | \
        --cert | --key | --cacert | --capath | -E | \
        --resolve | --interface | --dns-servers | --connect-to | \
        --hostpubmd5 | --hostpubsha256 | --pinnedpubkey | --tls-max | \
        --tlsuser | --tlspassword | --range | -r | --speed-limit | --speed-time)
        ((i += 2)) || true
        ;;

      # === Combined short flags (e.g. -sL, -sLI) ===
      # Letters that imply write/upload/data/method: o O T c d F K X
      -[!-]*)
        letters="${tok#-}"
        if [[ "$letters" == *[oOTcdFKX]* ]]; then
          ask "curl short-flag bundle '$tok' contains write/upload/data/method flag"
          return 0
        fi
        ((i++)) || true
        ;;

      # === URL token ===
      http://* | https://* | ftp://* | ftps://* | file://*)
        urls+=("$tok")
        ((i++)) || true
        ;;

      *)
        ((i++)) || true
        ;;
    esac
  done

  # === Domain allow-list check (only in "domains" mode) ===
  # In "off" / "all" mode, behave as before — allow any read-only fetch.
  # In "domains" mode, every fetched URL must match WEB_DOMAINS or we ask.
  if [[ "${WEB_MODE:-off}" == "domains" && ${#urls[@]} -gt 0 ]]; then
    local url domain
    for url in "${urls[@]+"${urls[@]}"}"; do
      domain=$(web_extract_domain "$url")
      if ! web_domain_matches "$domain"; then
        ask "curl to $domain (not in web-permissions allow-list)"
        return 0
      fi
    done
    allow "curl to allow-listed domain(s)"
    return 0
  fi

  allow "curl is a read-only HTTP request"
}
