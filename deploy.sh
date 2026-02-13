#!/usr/bin/env bash
# deploy.sh - Deploy Claude Code skills and optionally scripts
# Idempotent: safe to re-run (overwrites existing symlinks with -sf)
#
# Usage:
#   ./deploy.sh                      # Deploy skills globally to ~/.claude/commands/
#   ./deploy.sh --on-path            # Deploy skills + symlink scripts to ~/.local/bin/
#   ./deploy.sh --project /path      # Deploy skills to /path/.claude/commands/
#   ./deploy.sh --project /path --on-path  # Error: --on-path not supported with --project

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

PROJECT_PATH=""
ON_PATH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --on-path)
            ON_PATH=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -n "$PROJECT_PATH" && "$ON_PATH" == true ]]; then
    echo "Error: --on-path is not supported with --project" >&2
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

mkdir -p "$COMMANDS_BASE"
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

    target_dir="$COMMANDS_BASE/$tool_name"
    ln -sfn "$tool_dir" "$target_dir"
    echo "Linked: $target_dir"

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

echo ""
if [[ -n "$PROJECT_PATH" ]]; then
    echo "Deployed to: $COMMANDS_BASE"
else
    echo "Deployed to: ~/.claude/commands"
fi
if [[ "$ON_PATH" == true ]]; then
    echo "Scripts linked to: ~/.local/bin"
fi
echo "Ensure Claude Code can read the skill files."