#!/usr/bin/env bash
# sync.sh — vendor shared utils into each consuming plugin's scripts/ dir.
#
# The canonical source of shared scripts lives in utils/. Claude Code's Linux
# installer drops symlinks when copying the plugin into ~/.claude/plugins/cache,
# so plugins can't rely on `scripts/foo.sh -> ../../../utils/foo.sh` at runtime.
# Instead, each consuming plugin carries a real copy of every util it needs.
#
# Edit the canonical file in utils/, run this script, commit the result.
# CI calls `sync.sh --check` to fail on drift.
#
# Usage:
#   utils/sync.sh          # copy canonical → each plugin's scripts/
#   utils/sync.sh --check  # exit non-zero on drift, no changes

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-sync}"

# Vendoring manifest: PLUGIN → space-separated list of utils/ filenames.
# Every plugin listed below will receive a real copy of each util in its
# plugins-claude/<plugin>/scripts/ directory. Keys are quoted because shfmt
# otherwise reformats hyphens as arithmetic operators.
declare -A NEEDS=(
  ["convert-doc"]="approve-own-scripts.sh hook-compat.sh"
  ["elevated-edit"]="approve-own-scripts.sh hook-compat.sh"
  ["format-on-save"]="approve-own-scripts.sh hook-compat.sh"
  ["frontmatter-query"]="approve-own-scripts.sh hook-compat.sh"
  ["git-tools"]="approve-own-scripts.sh hook-compat.sh git-cli"
  ["image"]="approve-own-scripts.sh hook-compat.sh"
  ["jar-explore"]="approve-own-scripts.sh hook-compat.sh"
  ["kb-capture"]="approve-own-scripts.sh hook-compat.sh detect-schema.sh validate-frontmatter.sh"
  ["markdown"]="approve-own-scripts.sh hook-compat.sh"
  ["maven-indexer"]="approve-own-scripts.sh hook-compat.sh"
  ["maven-tools"]="approve-own-scripts.sh hook-compat.sh"
  ["notify-on-stop"]="approve-own-scripts.sh hook-compat.sh"
  ["permission-manager"]="approve-own-scripts.sh hook-compat.sh"
  ["session"]="approve-own-scripts.sh hook-compat.sh git-cli"
  ["session-history-analyzer"]="approve-own-scripts.sh hook-compat.sh"
  ["statusline"]="approve-own-scripts.sh hook-compat.sh"
  ["stl-game-config"]="approve-own-scripts.sh hook-compat.sh"
)

drift=0
synced=0

for plugin in "${!NEEDS[@]}"; do
  for util in ${NEEDS[$plugin]}; do
    src="$ROOT/utils/$util"
    dst="$ROOT/plugins-claude/$plugin/scripts/$util"

    if [[ ! -f "$src" ]]; then
      echo "ERROR: canonical source missing: utils/$util" >&2
      exit 1
    fi

    if [[ ! -d "$ROOT/plugins-claude/$plugin" ]]; then
      echo "ERROR: plugin dir missing: plugins-claude/$plugin" >&2
      exit 1
    fi

    case "$MODE" in
      --check)
        if [[ -L "$dst" ]]; then
          echo "DRIFT: $dst is a symlink (run utils/sync.sh)" >&2
          drift=1
        elif [[ ! -f "$dst" ]]; then
          echo "DRIFT: $dst missing (run utils/sync.sh)" >&2
          drift=1
        elif ! cmp -s "$src" "$dst"; then
          echo "DRIFT: $dst differs from utils/$util (run utils/sync.sh)" >&2
          drift=1
        fi
        ;;
      sync)
        [[ -L "$dst" ]] && rm "$dst"
        if ! cmp -s "$src" "$dst" 2>/dev/null; then
          cp -p "$src" "$dst"
          synced=$((synced + 1))
          echo "synced: plugins-claude/$plugin/scripts/$util"
        fi
        ;;
      *)
        echo "Usage: $0 [--check]" >&2
        exit 2
        ;;
    esac
  done
done

if [[ "$MODE" == "--check" ]]; then
  [[ $drift -eq 0 ]] || exit 1
  echo "no drift — all vendored copies match utils/"
elif [[ $synced -eq 0 ]]; then
  echo "already in sync — nothing to do"
else
  echo "$synced file(s) synced"
fi
