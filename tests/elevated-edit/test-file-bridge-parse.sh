#!/usr/bin/env bash
# test-file-bridge-parse.sh — assertions for parse_source() in file-bridge.
# Covers ssh-alias detection (bare host:path), explicit user@host:path,
# absolute/relative/tilde local paths, and the colon-without-slash ambiguity.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../plugins-claude/elevated-edit/scripts/file-bridge"

# Source the script — its main guard prevents auto-execution.
# shellcheck source=/dev/null
source "$SCRIPT"

PASS=0
FAIL=0

assert_parse() {
  local label="$1" input="$2" want_remote="$3" want_host="$4" want_path="$5"

  parse_source "$input"

  if [[ "$IS_REMOTE" == "$want_remote" && "$REMOTE_HOST" == "$want_host" && "$REMOTE_PATH" == "$want_path" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "      input:  %s\n" "$input"
    printf "      want:   IS_REMOTE=%s REMOTE_HOST=%q REMOTE_PATH=%q\n" "$want_remote" "$want_host" "$want_path"
    printf "      got:    IS_REMOTE=%s REMOTE_HOST=%q REMOTE_PATH=%q\n" "$IS_REMOTE" "$REMOTE_HOST" "$REMOTE_PATH"
    ((FAIL++)) || true
  fi
}

echo "── parse_source: remote forms ──"
assert_parse "bare host:path (ssh alias, the bug fix)" \
  "apollo:/etc/hosts" true "apollo" "/etc/hosts"
assert_parse "user@host:path (explicit user)" \
  "root@apollo:/etc/hosts" true "root@apollo" "/etc/hosts"
assert_parse "host:path with relative remote path" \
  "apollo:relative/file" true "apollo" "relative/file"
assert_parse "user@host:path with tilde-relative remote" \
  "logan@apollo:~/.bashrc" true "logan@apollo" "~/.bashrc"

echo "── parse_source: local forms ──"
assert_parse "absolute local path" \
  "/etc/hosts" false "" "/etc/hosts"
assert_parse "relative local path with ./" \
  "./relative/file" false "" "./relative/file"
assert_parse "plain relative local path" \
  "file.txt" false "" "file.txt"
assert_parse "tilde local path expands" \
  "~/file" false "" "$HOME/file"
assert_parse "absolute path containing a colon" \
  "/tmp/weird:name" false "" "/tmp/weird:name"

echo "── parse_source: documented limitation ──"
# scp/rsync convention: a relative path with a colon before the first '/'
# is treated as remote. Users with such filenames must prefix './'.
assert_parse "ambiguous 'weird:name' parses as remote (scp semantics)" \
  "weird:name/file" true "weird" "name/file"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
exit $((FAIL > 0 ? 1 : 0))
