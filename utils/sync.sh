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
# Vendoring is target-aware: each harness (plugins-claude/, plugins-opencode/)
# has its own manifest because the two harnesses consume different util sets
# per plugin (e.g. opencode git-tools vendors branch + sitrep; claude git-tools
# does not). A plugin dir listed in a manifest must already exist; --check
# covers every target, so OpenCode drift fails CI the same way Claude drift
# does.
#
# Usage:
#   utils/sync.sh          # copy canonical → each target's plugin scripts/
#   utils/sync.sh --check  # exit non-zero on drift, no changes

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-sync}"

# Vendoring manifests: PLUGIN → space-separated list of utils/ filenames,
# per target. Every plugin listed receives a real copy of each util in its
# <target>/<plugin>/scripts/ directory. Keys are quoted because shfmt
# otherwise reformats hyphens as arithmetic operators.
declare -A NEEDS_CLAUDE=(
	["format-on-save"]="hook-compat.sh"
	["git-tools"]="git-wait"
	["kb-capture"]="detect-schema.sh validate-frontmatter.sh"
	["inbox"]="inbox"
	["notify-on-stop"]="hook-compat.sh inbox"
	# branch and sitrep are canonical in utils/ and vendored back here; they
	# used to live only in this plugin's scripts/ dir.
	["session"]="git-wait branch sitrep"
)

declare -A NEEDS_OPENCODE=(
	["git-tools"]="git-wait branch sitrep"
	["inbox"]="inbox"
	["session"]="git-wait branch sitrep"
)

drift=0
synced=0

for target in claude opencode; do
	declare -n NEEDS="NEEDS_${target^^}"
	target_dir="$ROOT/plugins-$target"

	for plugin in "${!NEEDS[@]}"; do
		for util in ${NEEDS[$plugin]}; do
			src="$ROOT/utils/$util"
			dst="$target_dir/$plugin/scripts/$util"

			if [[ ! -f "$src" ]]; then
				echo "ERROR: canonical source missing: utils/$util" >&2
				exit 1
			fi

			if [[ ! -d "$target_dir/$plugin" ]]; then
				echo "ERROR: plugin dir missing: plugins-$target/$plugin" >&2
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
					mkdir -p "$target_dir/$plugin/scripts"
					cp -p "$src" "$dst"
					synced=$((synced + 1))
					echo "synced: plugins-$target/$plugin/scripts/$util"
				fi
				;;
			*)
				echo "Usage: $0 [--check]" >&2
				exit 2
				;;
			esac
		done
	done
	unset -n NEEDS
done

if [[ "$MODE" == "--check" ]]; then
	[[ $drift -eq 0 ]] || exit 1
	echo "no drift — all vendored copies match utils/"
elif [[ $synced -eq 0 ]]; then
	echo "already in sync — nothing to do"
else
	echo "$synced file(s) synced"
fi
