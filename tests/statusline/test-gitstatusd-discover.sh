#!/usr/bin/env bash
# test-gitstatusd-discover.sh — Test harness for gitstatusd-discover.sh.
# Verifies find_gitstatusd() locates the daemon across $GITSTATUS_DAEMON, the
# self-bootstrap cache, Homebrew, and PATH, and that globbing the arch suffix
# works regardless of arm64/aarch64 naming.
#
# Usage: bash tests/statusline/test-gitstatusd-discover.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../../plugins-claude/statusline/scripts/gitstatusd-discover.sh"

# shellcheck source=/dev/null
source "$HELPER"

PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Run find_gitstatusd in an isolated environment.
# Args: home_dir  sandbox_bin  [daemon_path]
# Sets globals DISCOVER_OUT and DISCOVER_RC.
discover() {
  local home="$1" sandbox="$2" daemon="${3:-}"
  local out rc
  out=$(
    export HOME="$home"
    export PATH="$sandbox:/usr/bin:/bin"
    if [[ -n "$daemon" ]]; then
      export GITSTATUS_DAEMON="$daemon"
    else
      unset GITSTATUS_DAEMON
    fi
    find_gitstatusd
  ) && rc=0 || rc=$?
  DISCOVER_OUT="$out"
  DISCOVER_RC="$rc"
}

check() {
  local label="$1" expected_out="$2" expected_rc="$3"

  if [[ -n "$FILTER" ]] && ! echo "$label" | grep -qi "$FILTER"; then
    ((SKIP++)) || true
    return 0
  fi

  if [[ "$DISCOVER_OUT" == "$expected_out" && "$DISCOVER_RC" == "$expected_rc" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: out=%q rc=%s, got: out=%q rc=%s)\n" \
      "$label" "$expected_out" "$expected_rc" "$DISCOVER_OUT" "$DISCOVER_RC"
    ((FAIL++)) || true
  fi
}

mkexec() {
  mkdir -p "$(dirname "$1")"
  : >"$1"
  chmod +x "$1"
}

# ===== 1. $GITSTATUS_DAEMON override =====
echo "── \$GITSTATUS_DAEMON override ──"
home1="$TMP/h1"
sandbox1="$TMP/bin1"
daemon1="$TMP/custom/gitstatusd"
mkdir -p "$home1" "$sandbox1"
mkexec "$daemon1"
discover "$home1" "$sandbox1" "$daemon1"
check "GITSTATUS_DAEMON returned" "$daemon1" "0"

# A non-executable GITSTATUS_DAEMON is ignored (falls through to not-found).
daemon1b="$TMP/custom/not-exec"
mkdir -p "$(dirname "$daemon1b")"
: >"$daemon1b"
discover "$home1" "$sandbox1" "$daemon1b"
check "non-executable GITSTATUS_DAEMON ignored" "" "1"

# ===== 2. Self-bootstrap cache (arch glob) =====
echo "── Self-bootstrap cache ──"
home2="$TMP/h2"
sandbox2="$TMP/bin2"
mkdir -p "$sandbox2"
cache2="$home2/.cache/gitstatus/gitstatusd-${PLATFORM}-arm64"
mkexec "$cache2"
discover "$home2" "$sandbox2"
check "cache binary found via glob (arm64 suffix)" "$cache2" "0"

# ===== 3. Homebrew prefix =====
echo "── Homebrew ──"
home3="$TMP/h3"
sandbox3="$TMP/bin3"
brew_prefix="$TMP/brew/opt/gitstatus"
mkdir -p "$home3" "$sandbox3"
brew_bin="$brew_prefix/usrbin/gitstatusd-${PLATFORM}-arm64"
mkexec "$brew_bin"
# Fake brew that echoes the prefix for `--prefix gitstatus`.
cat >"$sandbox3/brew" <<EOF
#!/bin/bash
[[ "\$1" == "--prefix" && "\$2" == "gitstatus" ]] && echo "$brew_prefix"
EOF
chmod +x "$sandbox3/brew"
discover "$home3" "$sandbox3"
check "homebrew binary found via brew --prefix" "$brew_bin" "0"

# ===== 4. PATH =====
echo "── PATH ──"
home4="$TMP/h4"
sandbox4="$TMP/bin4"
mkdir -p "$home4"
mkexec "$sandbox4/gitstatusd"
discover "$home4" "$sandbox4"
check "gitstatusd found on PATH" "$sandbox4/gitstatusd" "0"

# ===== 5. Precedence: GITSTATUS_DAEMON wins over cache =====
echo "── Precedence ──"
home5="$TMP/h5"
sandbox5="$TMP/bin5"
mkdir -p "$sandbox5"
mkexec "$home5/.cache/gitstatus/gitstatusd-${PLATFORM}-arm64"
daemon5="$TMP/custom5/gitstatusd"
mkexec "$daemon5"
discover "$home5" "$sandbox5" "$daemon5"
check "GITSTATUS_DAEMON takes precedence over cache" "$daemon5" "0"

# ===== 6. Not found =====
echo "── Not found ──"
home6="$TMP/h6"
sandbox6="$TMP/bin6"
mkdir -p "$home6" "$sandbox6"
discover "$home6" "$sandbox6"
check "nothing installed → returns non-zero, empty output" "" "1"

# ===== Summary =====
echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
