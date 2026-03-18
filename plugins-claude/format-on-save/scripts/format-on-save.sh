#!/usr/bin/env bash
# format-on-save.sh — PostToolUse hook that auto-formats files after Edit/Write.
# Dispatches to the appropriate formatter based on file extension.
# Always exits 0 — never blocks Claude. Logs warnings/errors to stderr.

set -euo pipefail

PREFIX="[format-on-save]"

log_warn() { echo "$PREFIX WARN: $*" >&2; }
log_error() { echo "$PREFIX ERROR: $*" >&2; }

HOOK_INPUT=$(cat)
# shellcheck source=scripts/hook-compat.sh
source "$(dirname "$0")/hook-compat.sh"

file_path="$HOOK_FILE_PATH"
[[ -n "$file_path" ]] || exit 0
[[ -f "$file_path" ]] || exit 0

ext="${file_path##*.}"
# Handle dotfiles with no extension
[[ "$ext" != "$file_path" ]] || exit 0

# --- Formatter functions ---

fmt_shfmt() {
  if ! command -v shfmt >/dev/null 2>&1; then
    log_warn "shfmt not found — skipping $file_path"
    return 0
  fi
  if ! shfmt -w -i 2 -ci "$file_path" 2>&1; then
    log_error "shfmt failed (exit $?) on $file_path"
  fi
}

fmt_prettier() {
  if ! command -v prettier >/dev/null 2>&1; then
    log_warn "prettier not found — skipping $file_path"
    return 0
  fi
  if ! prettier --write "$file_path" 2>&1; then
    log_error "prettier failed (exit $?) on $file_path"
  fi
}

fmt_rumdl() {
  if ! command -v rumdl >/dev/null 2>&1; then
    log_warn "rumdl not found — skipping $file_path"
    return 0
  fi
  if ! rumdl check --fix "$file_path" 2>&1; then
    log_error "rumdl failed (exit $?) on $file_path"
  fi
}

fmt_google_java() {
  if ! command -v google-java-format >/dev/null 2>&1; then
    log_warn "google-java-format not found — skipping $file_path"
    return 0
  fi
  if ! google-java-format --replace "$file_path" 2>&1; then
    log_error "google-java-format failed (exit $?) on $file_path"
  fi
}

fmt_ktlint() {
  if ! command -v ktlint >/dev/null 2>&1; then
    log_warn "ktlint not found — skipping $file_path"
    return 0
  fi
  if ! ktlint --format "$file_path" 2>&1; then
    log_error "ktlint failed (exit $?) on $file_path"
  fi
}

fmt_cargo_fmt() {
  # Walk up from file's directory looking for Cargo.toml
  local dir
  dir="$(dirname "$file_path")"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/Cargo.toml" ]]; then
      if ! command -v cargo >/dev/null 2>&1; then
        log_warn "cargo not found — falling back to rustfmt for $file_path"
        fmt_rustfmt_direct
        return
      fi
      if ! cargo fmt --manifest-path "$dir/Cargo.toml" 2>&1; then
        log_error "cargo fmt failed (exit $?) on $file_path"
      fi
      return
    fi
    dir="$(dirname "$dir")"
  done
  # No Cargo.toml found — standalone .rs file
  fmt_rustfmt_direct
}

fmt_rustfmt_direct() {
  if ! command -v rustfmt >/dev/null 2>&1; then
    log_warn "rustfmt not found — skipping $file_path"
    return 0
  fi
  if ! rustfmt "$file_path" 2>&1; then
    log_error "rustfmt failed (exit $?) on $file_path"
  fi
}

fmt_taplo() {
  if ! command -v taplo >/dev/null 2>&1; then
    log_warn "taplo not found — skipping $file_path"
    return 0
  fi
  if ! taplo format "$file_path" 2>&1; then
    log_error "taplo failed (exit $?) on $file_path"
  fi
}

fmt_ruff() {
  if ! command -v ruff >/dev/null 2>&1; then
    log_warn "ruff not found — skipping $file_path"
    return 0
  fi
  if ! ruff format "$file_path" 2>&1; then
    log_error "ruff failed (exit $?) on $file_path"
  fi
}

# --- Dispatch by extension ---

case "$ext" in
  sh | bash) fmt_shfmt ;;
  js | ts | jsx | tsx | json | yml | yaml | css | html)
    fmt_prettier
    ;;
  md) fmt_rumdl ;;
  java) fmt_google_java ;;
  kt | kts) fmt_ktlint ;;
  rs) fmt_cargo_fmt ;;
  toml) fmt_taplo ;;
  py | pyi) fmt_ruff ;;
esac

exit 0
