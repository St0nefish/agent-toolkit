#!/bin/bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
INSTALL_SCRIPT="$CONFIG_DIR/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# ── Colors ────────────────────────────────────────────────────────────────────

red() { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
dim() { printf '\033[2m%s\033[0m' "$*"; }

ok() { echo "  $(green ✓) $*"; }
fail() { echo "  $(red ✗) $*"; }

# ── Parse flags ───────────────────────────────────────────────────────────────

CLEAN_ALL=false
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN_ALL=true ;;
  esac
done

# ── Remove statusLine from settings ──────────────────────────────────────────

echo "Removing status line configuration..."

if [[ -f "$SETTINGS_FILE" ]]; then
  if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
    updated=$(jq 'del(.statusLine)' "$SETTINGS_FILE")
    echo "$updated" >"$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    ok "Removed statusLine from $SETTINGS_FILE"
  else
    ok "No statusLine entry found in $SETTINGS_FILE"
  fi
else
  ok "No settings file found at $SETTINGS_FILE"
fi

echo ""

# ── Remove installed script ──────────────────────────────────────────────────

if [[ -f "$INSTALL_SCRIPT" ]]; then
  rm "$INSTALL_SCRIPT"
  ok "Removed $INSTALL_SCRIPT"
else
  ok "No installed script at $INSTALL_SCRIPT"
fi

# ── Optional: clean config and cache ─────────────────────────────────────────

if [[ "$CLEAN_ALL" == "true" ]]; then
  echo ""
  echo "Cleaning config and cache..."

  if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
    ok "Removed cache: $CACHE_DIR"
  fi

  if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    ok "Removed config: $CONFIG_DIR"
  fi
fi

echo ""
echo "$(green "Done!") Status line has been removed."
echo "  $(dim "Restart Claude Code or start a new session for changes to take effect.")"
echo ""
