#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE_SH="$SCRIPT_DIR/statusline.sh"
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline"
INSTALL_SCRIPT="$INSTALL_DIR/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
OPT_OUT_MARKER="${XDG_STATE_HOME:-$HOME/.local/state}/claude-statusline/auto-install-disabled"

# ── Colors ────────────────────────────────────────────────────────────────────

red() { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
dim() { printf '\033[2m%s\033[0m' "$*"; }

ok() { echo "  $(green ✓) $*"; }
fail() { echo "  $(red ✗) $*"; }

# ── Dependency checks ────────────────────────────────────────────────────────

echo "Checking dependencies..."

# jq edits settings.json; git is read by the mod itself. Nothing else is needed.
missing=0
for tool in jq git; do
  if command -v "$tool" &>/dev/null; then
    ok "$tool $(dim "($(command -v "$tool"))")"
  else
    fail "$tool — install with: apt install $tool / brew install $tool"
    missing=1
  fi
done

echo ""

if ((missing)); then
  fail "Missing required dependencies. Install them and re-run."
  exit 1
fi

# ── Install the statusLine stub to a stable location ────────────────────────

echo "Installing statusLine stub..."
mkdir -p "$INSTALL_DIR" "$CACHE_DIR"
# An explicit setup re-enables automatic install/refresh on session start
rm -f "$OPT_OUT_MARKER"
cp "$STATUSLINE_SH" "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"
ok "Copied to $INSTALL_SCRIPT"
echo ""

# ── Configure Claude settings ────────────────────────────────────────────────

echo "Configuring Claude Code status line..."

if [[ ! -d "$HOME/.claude" ]]; then
  fail "$HOME/.claude does not exist — is Claude Code installed?"
  exit 1
fi

# The statusLine object points at the stable install location
statusline_json=$(jq -n \
  --arg cmd "bash $INSTALL_SCRIPT" \
  '{type: "command", command: $cmd, refresh: 150}')

if [[ -f "$SETTINGS_FILE" ]]; then
  updated=$(jq --argjson sl "$statusline_json" '.statusLine = $sl' "$SETTINGS_FILE")
  echo "$updated" >"$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  ok "Updated $SETTINGS_FILE"
else
  jq -n --argjson sl "$statusline_json" '{statusLine: $sl}' >"$SETTINGS_FILE"
  ok "Created $SETTINGS_FILE"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "$(green "Done!") claude-statusline is installed."
echo ""
echo "  Stub:     $(dim "$INSTALL_SCRIPT")"
echo "  Lines:    $(dim "$CACHE_DIR")"
echo "  Settings: $(dim "$SETTINGS_FILE")"
echo ""
echo "  $(dim "The mod draws the line; the stub only prints it. Restart Claude Code or start a new session to see it.")"
echo ""
