#!/usr/bin/env bash
# Run deploy-rs cargo tests.
# Usage: bash deploy-rs/test.sh [cargo-test-args...]
set -euo pipefail

if ! command -v cargo &>/dev/null; then
  echo "Error: cargo not found. Install Rust via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cargo test --manifest-path "$SCRIPT_DIR/Cargo.toml" "$@"
