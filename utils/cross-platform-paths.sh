#!/usr/bin/env bash
# cross-platform-paths.sh — Resolve Claude Code data paths across platforms.
#
# Source this file to get helper functions for locating Claude Code
# configuration and project directories:
#
#   source "$(dirname "$0")/cross-platform-paths.sh"
#
# Functions (all safe to call repeatedly, no side effects):
#   claude_platform             — "darwin" or "linux"
#   claude_data_dir             — absolute path to ~/.claude
#   claude_global_settings      — absolute path to global settings.json
#   claude_project_settings     — relative path to project settings.json
#   encode_project_path PATH   — encode a path for use as a project dir name
#   decode_project_path ENC    — best-effort reverse of encode (lossy)
#   claude_project_dir PATH    — full path to the project dir for PATH
#   claude_all_project_dirs    — list all project directories, one per line

# Detect platform: "darwin" or "linux"
claude_platform() {
  uname -s | tr '[:upper:]' '[:lower:]'
}

# Base Claude Code data directory
claude_data_dir() {
  printf '%s/.claude' "$HOME"
}

# Global settings file (absolute path)
claude_global_settings() {
  printf '%s/.claude/settings.json' "$HOME"
}

# Project-local settings file (relative path)
claude_project_settings() {
  printf '.claude/settings.json'
}

# Encode an absolute path into the directory name Claude Code uses.
# Replaces / and . with - (e.g., /Users/foo/.bar -> -Users-foo--bar).
encode_project_path() {
  local path="${1:-}"
  [[ -z "$path" ]] && return 0
  # Strip trailing slash
  path="${path%/}"
  printf '%s' "$path" | tr '/.' '-'
}

# Best-effort reverse of encode_project_path.
# Lossy: original hyphens, slashes, and dots all became '-' so the
# mapping is not injective.  Converts all '-' back to '/'.
decode_project_path() {
  local encoded="${1:-}"
  [[ -z "$encoded" ]] && return 0
  printf '%s' "$encoded" | tr '-' '/'
}

# Full path to the per-project data directory for a given project path.
claude_project_dir() {
  local path="${1:-}"
  [[ -z "$path" ]] && return 0
  local encoded
  encoded=$(encode_project_path "$path")
  printf '%s/.claude/projects/%s' "$HOME" "$encoded"
}

# List all existing project directories under ~/.claude/projects/,
# one per line. Outputs nothing if the directory does not exist.
claude_all_project_dirs() {
  local base
  base="$(claude_data_dir)/projects"
  [[ -d "$base" ]] || return 0
  for dir in "$base"/*/; do
    # Guard against the glob returning the literal pattern when empty
    [[ -d "$dir" ]] || continue
    printf '%s\n' "${dir%/}"
  done
}
