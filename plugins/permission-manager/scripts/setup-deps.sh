#!/usr/bin/env bash
# setup-deps.sh — Install shfmt and jq dependencies for bash-safety hook.
# Detects OS/package manager and installs missing dependencies.
set -euo pipefail

check_and_install() {
  local missing=()
  command -v shfmt &>/dev/null || missing+=("shfmt")
  command -v jq &>/dev/null || missing+=("jq")

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All dependencies already installed."
    shfmt --version
    jq --version
    return 0
  fi

  echo "Missing: ${missing[*]}"

  if command -v brew &>/dev/null; then
    echo "Installing via Homebrew..."
    brew install "${missing[@]}"
  elif command -v apt-get &>/dev/null; then
    echo "Installing via apt..."
    sudo apt-get update && sudo apt-get install -y "${missing[@]}"
  elif command -v dnf &>/dev/null; then
    echo "Installing via dnf..."
    sudo dnf install -y "${missing[@]}"
  elif command -v pacman &>/dev/null; then
    echo "Installing via pacman..."
    sudo pacman -S --noconfirm "${missing[@]}"
  elif command -v go &>/dev/null; then
    if [[ " ${missing[*]} " =~ " shfmt " ]]; then
      echo "Installing shfmt via go install..."
      go install mvdan.cc/sh/v3/cmd/shfmt@latest
    fi
    if [[ " ${missing[*]} " =~ " jq " ]]; then
      echo "ERROR: jq must be installed via system package manager."
      echo "  See: https://jqlang.github.io/jq/download/"
      exit 1
    fi
  else
    echo "ERROR: No supported package manager found. Install manually:"
    echo "  shfmt: https://github.com/mvdan/sh/releases"
    echo "  jq:    https://jqlang.github.io/jq/download/"
    exit 1
  fi

  echo "Done. Verifying..."
  shfmt --version
  jq --version
}

check_and_install
