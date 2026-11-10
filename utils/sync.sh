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

# Vendoring manifests: PLUGIN → space-separated list of utils/ entries,
# per target. An entry is `util` (vendored into <plugin>/scripts/) or
# `util:dir` (vendored into <plugin>/dir/). Every plugin listed receives a
# real copy of each entry. Keys are quoted because shfmt otherwise
# reformats hyphens as arithmetic operators.
#
# Markdown entries vendored for the opencode target are rendered through
# utils/opencode-port.py (harness mapping: script paths, worktree/plan/
# question/subagent surfaces). Claude always receives the byte-identical
# canonical file.
declare -A NEEDS_CLAUDE=(
	["format-on-save"]="hook-compat.sh"
	["git-tools"]="git-wait"
	["kb-capture"]="detect-schema.sh validate-frontmatter.sh"
	["inbox"]="inbox"
	["notify-on-stop"]="hook-compat.sh inbox"
	# branch, sitrep, and spine.md are canonical in utils/ and vendored back
	# here; they used to live only in this plugin's scripts/ dir.
	["session"]="git-wait branch sitrep spine.md:reference"
)

declare -A NEEDS_OPENCODE=(
	# OpenCode skills get a private base dir (paths in SKILL.md resolve
	# relative to it), so scripts are vendored into the skill dir that uses
	# them, not the plugin root. Keys may be nested paths.
	["git-tools/skills/git-wait"]="git-wait"
	["git-tools/skills/ship"]="git-wait"
	["inbox"]="inbox"
	["session/skills/session-start"]="git-wait branch spine.md:reference"
	["session/skills/session-issue"]="git-wait branch spine.md:reference"
	["session/skills/session-end"]="git-wait sitrep"
	["session/skills/session-summarize"]="sitrep"
	["session/skills/session-orchestrate"]="git-wait sitrep spine.md:reference"
)

# render_for_target <target> <src> — content on stdout, harness-adjusted.
render_for_target() {
	local target="$1" src="$2"
	if [[ "$target" == "opencode" && "$src" == *.md ]]; then
		python3 "$ROOT/utils/opencode-port.py" <"$src"
	else
		cat "$src"
	fi
}

drift=0
synced=0
TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

# mode_drift <src> <dst> — true when the exec bits differ. Git only tracks the
# exec bit, so that is the mode that matters for vendored copies; a checkout
# or merge that drops +x on a script must not pass --check.
mode_drift() {
	local sx dx
	[[ -x "$1" ]] && sx=1 || sx=0
	[[ -x "$2" ]] && dx=1 || dx=0
	[[ $sx -ne $dx ]]
}

for target in claude opencode; do
	# namerefs + ${var^^} need bash >= 4.3 (already past the repo's floor;
	# macOS ships bash 3.2, so run this with a brew-installed bash)
	declare -n NEEDS="NEEDS_${target^^}"
	target_dir="$ROOT/plugins-$target"

	for plugin in "${!NEEDS[@]}"; do
		for entry in ${NEEDS[$plugin]}; do
			util="${entry%%:*}"
			subdir="${entry#*:}"
			[[ "$subdir" == "$entry" ]] && subdir="scripts"
			src="$ROOT/utils/$util"
			dst="$target_dir/$plugin/$subdir/$util"

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
				elif ! render_for_target "$target" "$src" >"$TMPOUT" || ! cmp -s "$TMPOUT" "$dst"; then
					echo "DRIFT: $dst differs from utils/$util (run utils/sync.sh)" >&2
					drift=1
				elif mode_drift "$src" "$dst"; then
					echo "DRIFT: $dst exec bit differs from utils/$util (run utils/sync.sh)" >&2
					drift=1
				fi
				;;
			sync)
				[[ -L "$dst" ]] && rm "$dst"
				render_for_target "$target" "$src" >"$TMPOUT"
				if ! cmp -s "$TMPOUT" "$dst" 2>/dev/null || { [[ -f "$dst" ]] && mode_drift "$src" "$dst"; }; then
					mkdir -p "$target_dir/$plugin/$subdir"
					cp "$TMPOUT" "$dst"
					# mktemp renders at 0600; apply the canonical mode instead
					# (group/other readable, exec bit only when the source has it)
					chmod 0644 "$dst"
					if [[ -x "$src" ]]; then
						chmod +x "$dst"
					fi
					synced=$((synced + 1))
					echo "synced: plugins-$target/$plugin/$subdir/$util"
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
