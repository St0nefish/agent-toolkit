#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE_SH="$SCRIPT_DIR/statusline.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline"
CONFIG_FILE="$CONFIG_DIR/config.json"
DEFAULT_CONFIG="$SCRIPT_DIR/config.json"
SETTINGS_FILE="$HOME/.claude/settings.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
INSTALL_DIR="$CONFIG_DIR"
INSTALL_SCRIPT="$INSTALL_DIR/statusline.sh"

# ── Colors ────────────────────────────────────────────────────────────────────

red() { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
dim() { printf '\033[2m%s\033[0m' "$*"; }

ok() { echo "  $(green ✓) $*"; }
warn() { echo "  $(yellow ⚠) $*"; }
fail() { echo "  $(red ✗) $*"; }

# ── Dependency checks ────────────────────────────────────────────────────────

echo "Checking dependencies..."

missing=0

check_tool() {
  local tool="$1" hint="${2:-}"
  if command -v "$tool" &>/dev/null; then
    ok "$tool $(dim "($(command -v "$tool"))")"
  else
    fail "$tool — $hint"
    missing=1
  fi
}

check_tool jq "install with: apt install jq / brew install jq"
check_tool curl "install with: apt install curl / brew install curl"
check_tool awk "should be pre-installed on all systems"
check_tool git "install with: apt install git / brew install git"

# Optional: gitstatusd for fast git status
platform=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
esac
gitstatusd_bin="$HOME/.cache/gitstatus/gitstatusd-${platform}-${arch}"
if [[ -x "$gitstatusd_bin" ]]; then
  ok "gitstatusd $(dim "(optional, found at $gitstatusd_bin)")"
else
  warn "gitstatusd not found $(dim "(optional — will use git CLI fallback)")"
fi

echo ""

if ((missing)); then
  fail "Missing required dependencies. Install them and re-run."
  exit 1
fi

# ── Setup directories ────────────────────────────────────────────────────────

echo "Setting up directories..."
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
ok "Config: $CONFIG_DIR"
ok "Cache:  $CACHE_DIR"
echo ""

# ── Copy statusline script to stable location ────────────────────────────────

echo "Installing statusline script..."
cp "$STATUSLINE_SH" "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"
ok "Copied to $INSTALL_SCRIPT"
echo ""

# ── Copy default config if none exists ────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Installing default config..."
  cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
  ok "Created $CONFIG_FILE"
  echo ""
else
  ok "Config already exists at $CONFIG_FILE"
  echo ""
fi

# ── Configure Claude settings ────────────────────────────────────────────────

echo "Configuring Claude Code status line..."

if [[ ! -d "$HOME/.claude" ]]; then
  fail "$HOME/.claude does not exist — is Claude Code installed?"
  exit 1
fi

# Build the statusLine object — points to the stable install location
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
echo "  Script:   $(dim "$INSTALL_SCRIPT")"
echo "  Config:   $(dim "$CONFIG_FILE")"
echo "  Cache:    $(dim "$CACHE_DIR")"
echo "  Settings: $(dim "$SETTINGS_FILE")"
echo ""
echo "  $(dim "Restart Claude Code or start a new session to see the status line.")"
echo ""
