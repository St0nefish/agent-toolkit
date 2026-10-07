#!/bin/bash
# SessionStart hook: install the statusline on first run, then keep the
# installed copy in step with the plugin version that just loaded.
#
# Plugins cannot set `statusLine` themselves, so this does what
# /statusline:statusline-setup does, silently:
#   - Not installed yet: copy the statusLine stub (statusline.sh) into
#     ~/.config/claude-statusline/ and add `statusLine` to ~/.claude/settings.json.
#     Strictly add-only: if settings already define a statusLine (ours or anyone
#     else's) nothing is written.
#   - Already installed: refresh the stub if the plugin's differs (this also replaces
#     the bash renderer of versions before 3.0 with the stub), so a plugin
#     update reaches the version-stable copy settings.json points at. If the
#     `statusLine` entry has since been removed, it is added back with the defaults.
#
# Opt out with CLAUDE_STATUSLINE_NO_AUTO_INSTALL=1, or by running
# /statusline:statusline-teardown (which leaves a marker so removal sticks). Re-running
# /statusline:statusline-setup clears the marker.
#
# The mod itself (hooks/register.tsx) loads with the plugin; the stub only prints
# the line it renders. An old config.json is left alone but no longer read.
# Silent on success: SessionStart stdout
# is injected into the model's context. Never fails the session; problems go to
# stderr only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
PURGE_DAYS=7
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-statusline"
OPT_OUT_MARKER="$STATE_DIR/auto-install-disabled"
SETTINGS_FILE="$HOME/.claude/settings.json"
FILES=(statusline.sh)
# Files an earlier version installed that nothing uses any more.
OBSOLETE=(gitstatusd-discover.sh)

# Copy SRC over DEST atomically (write beside it, then rename) so a statusline
# refresh mid-update never executes a half-written script.
install_file() {
  local src="$1" dest="$2" tmp
  [[ -f "$src" ]] || return 0
  cmp -s "$src" "$dest" && return 0
  tmp=$(mktemp "$(dirname "$dest")/.$(basename "$dest").XXXXXX") || {
    echo "statusline: cannot update $dest" >&2
    return 0
  }
  if cp "$src" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$dest"; then
    return 0
  fi
  rm -f "$tmp"
  echo "statusline: failed to update $dest" >&2
}

# True when settings.json already defines a statusLine.
settings_has_statusline() {
  [[ -f "$SETTINGS_FILE" ]] && jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null
}

# Add our statusLine to settings.json. Edits in place so ownership and mode of an
# existing file are preserved.
add_statusline_setting() {
  local entry updated
  entry=$(jq -n --arg cmd "bash $INSTALL_DIR/statusline.sh" \
    '{type: "command", command: $cmd, refreshInterval: 3}') || return 1

  if [[ -f "$SETTINGS_FILE" ]]; then
    updated=$(jq --argjson sl "$entry" '.statusLine = $sl' "$SETTINGS_FILE") || return 1
    [[ -n "$updated" ]] || return 1
    printf '%s\n' "$updated" >"$SETTINGS_FILE"
  else
    mkdir -p "$(dirname "$SETTINGS_FILE")" || return 1
    jq -n --argjson sl "$entry" '{statusLine: $sl}' >"$SETTINGS_FILE"
  fi
}

# Our own entry from before refreshInterval existed gets the default; a value the
# user set, or an entry that is not ours, is left alone. Written in place so the
# file keeps its owner and mode.
upgrade_statusline_setting() {
  [[ "${CLAUDE_STATUSLINE_NO_AUTO_INSTALL:-}" == "1" ]] && return 0
  [[ -e "$OPT_OUT_MARKER" ]] && return 0
  [[ -f "$SETTINGS_FILE" ]] || return 0
  local updated
  updated=$(jq --arg cmd "bash $INSTALL_DIR/statusline.sh" \
    'if .statusLine.command == $cmd and (.statusLine | has("refreshInterval") | not)
     then .statusLine.refreshInterval = 3 else empty end' "$SETTINGS_FILE" 2>/dev/null) || return 0
  [[ -n "$updated" ]] || return 0
  printf '%s\n' "$updated" >"$SETTINGS_FILE"
}

auto_install() {
  [[ "${CLAUDE_STATUSLINE_NO_AUTO_INSTALL:-}" == "1" ]] && return 0
  [[ -e "$OPT_OUT_MARKER" ]] && return 0
  # jq is required both to edit settings and by the statusline itself
  command -v jq &>/dev/null || return 0
  # Someone already owns the status line: leave it alone
  settings_has_statusline && return 0

  mkdir -p "$INSTALL_DIR" || return 0
  for f in "${FILES[@]}"; do
    install_file "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"
  done

  add_statusline_setting || {
    echo "statusline: could not update $SETTINGS_FILE" >&2
    return 0
  }
}

# Per-session line files are removed by the mod on a clean exit; a crashed or
# killed session leaves its file behind. Drop any untouched for a week (a live
# session rewrites its file on every turn).
find "$CACHE_DIR" -maxdepth 1 -type f -mtime +"$PURGE_DAYS" -delete 2>/dev/null

if [[ -f "$INSTALL_DIR/statusline.sh" ]]; then
  for f in "${OBSOLETE[@]}"; do
    rm -f "$INSTALL_DIR/$f"
  done
  for f in "${FILES[@]}"; do
    install_file "$SCRIPT_DIR/$f" "$INSTALL_DIR/$f"
  done
fi
# Adds the statusLine entry (with the plugin's defaults) whenever settings have
# none and the user has not opted out, so removing the entry restores the
# defaults at the next session start instead of leaving the line off.
auto_install
command -v jq &>/dev/null && upgrade_statusline_setting

exit 0
