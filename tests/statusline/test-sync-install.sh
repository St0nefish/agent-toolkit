#!/usr/bin/env bash
# test-sync-install.sh — Tests for the statusline SessionStart hook: first-run
# install into settings.json (add-only), refresh after a plugin update, and the
# opt-out / teardown marker.
#
# Usage: bash tests/statusline/test-sync-install.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$SCRIPT_DIR/../../plugins-claude/statusline"
SYNC="$PLUGIN/scripts/sync-install.sh"
SETUP="$PLUGIN/scripts/setup.sh"
TEARDOWN="$PLUGIN/scripts/teardown.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_STATE_HOME="$TMP/state"
export XDG_CACHE_HOME="$TMP/cache"
unset CLAUDE_STATUSLINE_NO_AUTO_INSTALL
INSTALL="$XDG_CONFIG_HOME/claude-statusline"
SETTINGS="$HOME/.claude/settings.json"
MARKER="$XDG_STATE_HOME/claude-statusline/auto-install-disabled"

PASS=0
FAIL=0
SKIP=0
FILTER="${1:-}"

filtered() {
  [[ -n "$FILTER" ]] && ! echo "$1" | grep -qi "$FILTER"
}

check() {
  local label="$1" expected="$2" actual="$3"
  if filtered "$label"; then
    ((SKIP++)) || true
    return 0
  fi
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s  (expected: %q, got: %q)\n" "$label" "$expected" "$actual"
    ((FAIL++)) || true
  fi
}

same() { cmp -s "$1" "$2" && echo same || echo differ; }
present() { [[ -e "$1" ]] && echo present || echo absent; }
sl_cmd() { jq -r '.statusLine.command // "none"' "$SETTINGS" 2>/dev/null || echo none; }

# Clean slate: no install, no settings, no marker
reset() {
  rm -rf "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
  mkdir -p "$HOME/.claude"
}

# Stand-in for a previously installed (stale) copy
install_stale() {
  mkdir -p "$INSTALL"
  printf '#!/bin/bash\necho old\n' >"$INSTALL/statusline.sh"
  printf '# old discover\n' >"$INSTALL/gitstatusd-discover.sh"
  printf '{"label_style":"long"}\n' >"$INSTALL/config.json"
  chmod 755 "$INSTALL/statusline.sh"
}

echo "── first run: nothing installed ──"
reset
OUT=$(bash "$SYNC" 2>&1)
check "silent (stdout reaches model context)" "" "$OUT"
check "statusline.sh installed" "same" "$(same "$PLUGIN/scripts/statusline.sh" "$INSTALL/statusline.sh")"
check "no gitstatusd helper installed" "absent" "$(present "$INSTALL/gitstatusd-discover.sh")"
check "no config.json created" "absent" "$(present "$INSTALL/config.json")"
check "settings.json created with statusLine" "bash $INSTALL/statusline.sh" "$(sl_cmd)"
check "statusLine type is command" "command" "$(jq -r '.statusLine.type' "$SETTINGS")"
check "installed script is executable" "755" "$(stat -c '%a' "$INSTALL/statusline.sh")"
check "no temp files left behind" "0" "$(find "$INSTALL" -name '.*.??????' | wc -l | tr -d ' ')"

echo "── first run: existing settings ──"
reset
printf '{"model":"opus","env":{"A":"1"}}\n' >"$SETTINGS"
chmod 600 "$SETTINGS"
bash "$SYNC"
check "statusLine added" "bash $INSTALL/statusline.sh" "$(sl_cmd)"
check "other settings preserved" "opus 1" "$(jq -r '"\(.model) \(.env.A)"' "$SETTINGS")"
check "settings file mode preserved" "600" "$(stat -c '%a' "$SETTINGS")"

echo "── first run: existing config kept ──"
reset
mkdir -p "$INSTALL"
printf '{"label_style":"long"}\n' >"$INSTALL/config.json"
bash "$SYNC"
check "user config.json not overwritten" '{"label_style":"long"}' "$(cat "$INSTALL/config.json")"

echo "── add-only: someone else owns statusLine ──"
reset
printf '{"statusLine":{"type":"command","command":"my-own-line"}}\n' >"$SETTINGS"
bash "$SYNC"
check "foreign statusLine untouched" "my-own-line" "$(sl_cmd)"
check "nothing installed" "absent" "$(present "$INSTALL/statusline.sh")"

echo "── opt-out ──"
reset
CLAUDE_STATUSLINE_NO_AUTO_INSTALL=1 bash "$SYNC"
check "env var → nothing installed" "absent" "$(present "$INSTALL/statusline.sh")"
check "env var → settings not created" "absent" "$(present "$SETTINGS")"
reset
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
bash "$SYNC"
check "marker → nothing installed" "absent" "$(present "$INSTALL/statusline.sh")"

echo "── teardown / setup markers ──"
reset
bash "$SYNC"
bash "$TEARDOWN" >/dev/null
check "teardown removes statusLine" "none" "$(sl_cmd)"
check "teardown leaves the opt-out marker" "present" "$(present "$MARKER")"
bash "$SYNC"
check "removal sticks across session start" "absent" "$(present "$INSTALL/statusline.sh")"
bash "$SETUP" >/dev/null
check "setup clears the marker" "absent" "$(present "$MARKER")"
check "setup re-installs statusLine" "bash $INSTALL/statusline.sh" "$(sl_cmd)"

echo "── setup/teardown edit settings in place ──"
reset
printf '{"model":"opus"}\n' >"$SETTINGS"
ino=$(stat -c '%i' "$SETTINGS")
bash "$SETUP" >/dev/null
check "setup keeps the settings.json inode" "$ino" "$(stat -c '%i' "$SETTINGS")"
bash "$TEARDOWN" >/dev/null
check "teardown keeps the settings.json inode" "$ino" "$(stat -c '%i' "$SETTINGS")"
check "teardown preserves other settings" "opus" "$(jq -r '.model' "$SETTINGS")"

echo "── purge of expired line files ──"
reset
mkdir -p "$XDG_CACHE_HOME/claude-statusline"
printf 'x\n' >"$XDG_CACHE_HOME/claude-statusline/old-id"
printf 'x\n' >"$XDG_CACHE_HOME/claude-statusline/fresh-id"
touch -d '8 days ago' "$XDG_CACHE_HOME/claude-statusline/old-id"
bash "$SYNC"
check "expired line file removed" "absent" "$(present "$XDG_CACHE_HOME/claude-statusline/old-id")"
check "recent line file kept" "present" "$(present "$XDG_CACHE_HOME/claude-statusline/fresh-id")"

echo "── refresh after plugin update ──"
reset
install_stale
OUT=$(bash "$SYNC" 2>&1)
check "silent on refresh" "" "$OUT"
check "statusline.sh refreshed" "same" "$(same "$PLUGIN/scripts/statusline.sh" "$INSTALL/statusline.sh")"
check "obsolete gitstatusd-discover.sh removed" "absent" "$(present "$INSTALL/gitstatusd-discover.sh")"
check "config.json left untouched" '{"label_style":"long"}' "$(cat "$INSTALL/config.json")"
check "refresh does not touch settings" "absent" "$(present "$SETTINGS")"

echo "── already current ──"
before=$(stat -c '%Y %i' "$INSTALL/statusline.sh")
sleep 1
bash "$SYNC"
check "identical copy is not rewritten" "$before" "$(stat -c '%Y %i' "$INSTALL/statusline.sh")"

echo "── the stub prints the line the mod rendered ──"
STUB="$PLUGIN/scripts/statusline.sh"
LINES="$XDG_CACHE_HOME/claude-statusline"
mkdir -p "$LINES"
printf 'rendered line\n' >"$LINES/abc-123"
check "prints this session's line" "rendered line" \
  "$(printf '{"session_id":"abc-123","model":{"id":"x"}}' | bash "$STUB")"
check "another session gets nothing" "" \
  "$(printf '{"session_id":"zzz"}' | bash "$STUB")"
check "no line written yet is not an error" "0" \
  "$(
    printf '{"session_id":"nope"}' | bash "$STUB" >/dev/null
    echo $?
  )"
check "waits for a line the mod writes just after startup" "late line" \
  "$(
    (
      sleep 0.5
      printf 'late line\n' >"$LINES/late-id"
    ) &
    printf '{"session_id":"late-id"}' | bash "$STUB"
  )"
check "a path-like id is refused" "" \
  "$(printf '{"session_id":"../abc-123"}' | bash "$STUB")"
check "no session id prints nothing" "" "$(printf '{}' | bash "$STUB")"

echo "── hook registration ──"
check "SessionStart runs sync-install.sh" "true" \
  "$(jq -r '[.hooks.SessionStart[].hooks[].command | contains("sync-install.sh")] | any' "$PLUGIN/hooks/hooks.json")"

echo ""
echo "Total: $((PASS + FAIL + SKIP))  PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
exit "$FAIL"
