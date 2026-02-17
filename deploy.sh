#!/usr/bin/env bash
# deploy.sh - Deploy Claude Code skills, tool scripts, and hooks
# Idempotent: safe to re-run (overwrites existing symlinks with -sf)
#
# Scripts deploy to:  ~/.claude/tools/<tool-name>/  (always)
# Skills deploy to:   ~/.claude/commands/ or <project>/.claude/commands/
# Hooks deploy to:    ~/.claude/hooks/<hook-name>/  (always global)
# --on-path also:     ~/.local/bin/  (symlinks to individual scripts)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
HOOKS_DIR="$SCRIPT_DIR/hooks"

PROJECT_PATH=""
ON_PATH=false
INCLUDE=""
EXCLUDE=""

usage() {
    cat <<EOF
Usage: ./deploy.sh [OPTIONS]

Deploy Claude Code skills, tool scripts, and hooks.

Scripts are always deployed to ~/.claude/tools/<tool-name>/.
Skills (.md files) are deployed to ~/.claude/commands/ (or a project).
Hooks are always deployed to ~/.claude/hooks/<hook-name>/ (global only).

Options:
  --project PATH         Deploy skills to PATH/.claude/commands/ instead of globally
  --on-path              Also symlink scripts to ~/.local/bin/ (global deploy only)
  --include tool1,tool2  Only deploy these tools (comma-separated)
  --exclude tool1,tool2  Deploy all tools EXCEPT these (comma-separated)
  -h, --help             Show this help message

--include and --exclude are mutually exclusive. Tool names match directory
names under tools/ (e.g., jar-explore, docker-pg-query).

When --project is used, skills already deployed globally (~/.claude/commands/)
are skipped to avoid conflicts.

Examples:
  ./deploy.sh                                    Deploy all tools
  ./deploy.sh --on-path                          Also symlink scripts to ~/.local/bin/
  ./deploy.sh --project /path/to/repo            Deploy skills to a specific project
  ./deploy.sh --include jar-explore              Deploy only jar-explore
  ./deploy.sh --exclude paste-image-wsl          Deploy everything except paste-image-wsl
  ./deploy.sh --include jar-explore --on-path    Deploy jar-explore with PATH symlinks
EOF
    exit 1
}

# Returns 0 (true = skip) if the tool should be filtered out by --include/--exclude
is_filtered_out() {
    local tool_name="$1"
    if [[ -n "$INCLUDE" ]]; then
        # Only deploy tools in the include list
        if [[ ",$INCLUDE," != *",$tool_name,"* ]]; then
            return 0
        fi
    elif [[ -n "$EXCLUDE" ]]; then
        # Skip tools in the exclude list
        if [[ ",$EXCLUDE," == *",$tool_name,"* ]]; then
            return 0
        fi
    fi
    return 1
}

# Returns 0 (true = skip) if the skill .md already exists in global commands.
# Checks both top-level (single-md tools) and subdirectory (multi-md tools).
is_globally_deployed() {
    local md_path="$1"
    local md_name tool_name
    md_name="$(basename "$md_path")"
    tool_name="$(basename "$(dirname "$md_path")")"
    [[ -L "$HOME/.claude/commands/$md_name" ]] || [[ -L "$HOME/.claude/commands/$tool_name/$md_name" ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --on-path)
            ON_PATH=true
            shift
            ;;
        --include)
            INCLUDE="$2"
            shift 2
            ;;
        --exclude)
            EXCLUDE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

if [[ -n "$PROJECT_PATH" && "$ON_PATH" == true ]]; then
    echo "Error: --on-path is not supported with --project" >&2
    exit 1
fi

if [[ -n "$INCLUDE" && -n "$EXCLUDE" ]]; then
    echo "Error: --include and --exclude are mutually exclusive" >&2
    exit 1
fi

COMMANDS_BASE="$HOME/.claude/commands"
if [[ -n "$PROJECT_PATH" ]]; then
    COMMANDS_BASE="$PROJECT_PATH/.claude/commands"
    if [[ ! -d "$PROJECT_PATH" ]]; then
        echo "Error: Project directory does not exist: $PROJECT_PATH" >&2
        exit 1
    fi
fi

TOOLS_BASE="$HOME/.claude/tools"

mkdir -p "$COMMANDS_BASE"
mkdir -p "$TOOLS_BASE"
if [[ "$ON_PATH" == true ]]; then
    mkdir -p "$HOME/.local/bin"
fi

if [[ ! -d "$TOOLS_DIR" ]]; then
    echo "No tools/ directory found."
    exit 0
fi

for tool_dir in "$TOOLS_DIR"/*/; do
    tool_name="$(basename "$tool_dir")"

    if [[ -x "$tool_dir/condition.sh" ]]; then
        if ! "$tool_dir/condition.sh" >/dev/null 2>&1; then
            echo "Skipped: $tool_name (condition not met)"
            continue
        fi
    fi

    if is_filtered_out "$tool_name"; then
        echo "Skipped: $tool_name (filtered out)"
        continue
    fi

    # --- Deploy scripts: symlink tool directory to ~/.claude/tools/<tool-name> ---
    ln -sfn "$tool_dir" "$TOOLS_BASE/$tool_name"
    echo "Linked: ~/.claude/tools/$tool_name"

    # --- Deploy skills: symlink .md files (excluding README.md) to commands ---
    md_files=()
    for md in "$tool_dir"/*.md; do
        [[ -f "$md" ]] || continue
        [[ "$(basename "$md")" == "README.md" ]] && continue
        md_files+=("$md")
    done

    if [[ ${#md_files[@]} -eq 1 ]]; then
        # Single skill: symlink directly as commands/<md-filename>
        md_name="$(basename "${md_files[0]}")"
        if [[ -n "$PROJECT_PATH" ]] && is_globally_deployed "${md_files[0]}"; then
            echo "Skipped: $tool_name skill (already deployed globally)"
        else
            ln -sf "${md_files[0]}" "$COMMANDS_BASE/$md_name"
            echo "Linked: $COMMANDS_BASE/$md_name"
        fi
    elif [[ ${#md_files[@]} -gt 1 ]]; then
        # Multiple skills: create subdirectory and symlink each
        local_skip_count=0
        if [[ -n "$PROJECT_PATH" ]]; then
            for md in "${md_files[@]}"; do
                if is_globally_deployed "$md"; then
                    ((local_skip_count++))
                fi
            done
        fi
        if [[ -n "$PROJECT_PATH" && "$local_skip_count" -eq ${#md_files[@]} ]]; then
            echo "Skipped: $tool_name skills (already deployed globally)"
        else
            mkdir -p "$COMMANDS_BASE/$tool_name"
            for md in "${md_files[@]}"; do
                md_name="$(basename "$md")"
                if [[ -n "$PROJECT_PATH" ]] && is_globally_deployed "$md"; then
                    echo "Skipped: $tool_name/$md_name (already deployed globally)"
                else
                    ln -sf "$md" "$COMMANDS_BASE/$tool_name/$md_name"
                    echo "Linked: $COMMANDS_BASE/$tool_name/$md_name"
                fi
            done
        fi
    fi

    # --- Clean up stale old-style directory symlink if present ---
    # Old deploy.sh symlinked the entire tool dir to commands/<tool-name>.
    # If that symlink still exists and points to a tools/ source dir, remove it.
    old_link="$COMMANDS_BASE/$tool_name"
    if [[ -L "$old_link" && -d "$old_link" ]]; then
        link_target="$(readlink "$old_link")"
        if [[ "$link_target" == */tools/* ]]; then
            rm "$old_link"
            echo "Cleaned: stale directory symlink $old_link"
        fi
    fi

    # --- Optionally symlink scripts to ~/.local/bin/ ---
    if [[ "$ON_PATH" == true ]] && [[ -d "$tool_dir/bin" ]]; then
        for script in "$tool_dir"/bin/*; do
            [[ -f "$script" ]] || continue
            script_name="$(basename "$script")"
            ln -sf "$script" "$HOME/.local/bin/$script_name"
            echo "Linked: ~/.local/bin/$script_name"
        done
    fi

    echo "Deployed: $tool_name"
done

# ===== Deploy hooks =====
HOOKS_BASE="$HOME/.claude/hooks"

if [[ -d "$HOOKS_DIR" ]]; then
    mkdir -p "$HOOKS_BASE"
    for hook_dir in "$HOOKS_DIR"/*/; do
        [[ -d "$hook_dir" ]] || continue
        hook_name="$(basename "$hook_dir")"

        if [[ -x "$hook_dir/condition.sh" ]]; then
            if ! "$hook_dir/condition.sh" >/dev/null 2>&1; then
                echo "Skipped: hook $hook_name (condition not met)"
                continue
            fi
        fi

        if is_filtered_out "$hook_name"; then
            echo "Skipped: hook $hook_name (filtered out)"
            continue
        fi

        ln -sfn "$hook_dir" "$HOOKS_BASE/$hook_name"
        echo "Linked: ~/.claude/hooks/$hook_name"
        echo "Deployed: hook $hook_name"
    done
fi

echo ""
if [[ -n "$PROJECT_PATH" ]]; then
    echo "Deployed to: $COMMANDS_BASE"
else
    echo "Deployed to: ~/.claude/commands (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
fi
if [[ "$ON_PATH" == true ]]; then
    echo "Scripts also linked to: ~/.local/bin"
fi
