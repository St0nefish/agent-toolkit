# shellcheck shell=bash
# shellcheck source=../lib-classify.sh

# --- Destructive find operations ---
check_find() {
  echo "$command" | perl -ne '$f=1,last if /^\s*find\s/; END{exit !$f}' || return 0

  if echo "$command" | perl -ne '$f=1,last if /\s-delete\b/; END{exit !$f}'; then
    deny "find -delete can remove files"
    return 0
  fi

  if echo "$command" | perl -ne '$f=1,last if /\s-(exec|execdir|ok|okdir)\s/; END{exit !$f}'; then
    local unsafe
    unsafe=$(echo "$command" |
      perl -ne 'while (/-(exec|execdir|ok|okdir)\s+(\S+)/g) { print "$2\n" }' |
      while read -r cmd; do
        base=$(basename "$cmd" 2>/dev/null || echo "$cmd")
        case "$base" in
          grep | egrep | fgrep | rg | cat | head | tail | less | more | file | stat | ls | wc | jq | \
            sort | uniq | cut | tr | strings | xxd | od | hexdump | md5sum | sha256sum | sha1sum | \
            readlink | realpath | basename | dirname | test | \[) ;;
          *)
            echo "$base"
            ;;
        esac
      done)
    if [[ -n "$unsafe" ]]; then
      deny "find -exec with '$(echo "$unsafe" | head -1)' is not in the read-only safe list"
      return 0
    fi
  fi

  # find without dangerous flags is a read-only file search
  allow "find is read-only file search"
}
