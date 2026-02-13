#!/usr/bin/env bash
# deploy.sh - Deploy tools from tools/<name>/ into ~/.local/bin and ~/.claude/commands
# Idempotent: safe to re-run (overwrites existing symlinks with -sf)
#
# For each tool folder:
#   - If condition.sh exists and exits non-zero, skip the tool
#   - Symlink bin/* to ~/.local/bin/
#   - Symlink skill .md files to ~/.claude/commands/:
#       1 .md file  -> symlink file to ~/.claude/commands/<md-filename>
#       N .md files -> symlink folder to ~/.claude/commands/<folder-name>/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.claude/commands"

if [[ ! -d "$TOOLS_DIR" ]]; then
    echo "No tools/ directory found."
    exit 0
fi

for tool_dir in "$TOOLS_DIR"/*/; do
    tool_name="$(basename "$tool_dir")"

    # Check condition gate
    if [[ -x "$tool_dir/condition.sh" ]]; then
        if ! "$tool_dir/condition.sh" >/dev/null 2>&1; then
            echo "Skipped: $tool_name (condition not met)"
            continue
        fi
    fi

    # Symlink bin scripts
    if [[ -d "$tool_dir/bin" ]]; then
        for script in "$tool_dir"/bin/*; do
            [[ -f "$script" ]] || continue
            name="$(basename "$script")"
            ln -sf "$script" "$HOME/.local/bin/$name"
            echo "Linked: ~/.local/bin/$name"
        done
    fi

    # Symlink skill definitions
    md_files=()
    for md in "$tool_dir"/*.md; do
        [[ -f "$md" ]] || continue
        md_files+=("$md")
    done

    if [[ ${#md_files[@]} -eq 1 ]]; then
        # Single .md file: symlink to ~/.claude/commands/<md-filename>
        md_name="$(basename "${md_files[0]}")"
        ln -sf "${md_files[0]}" "$HOME/.claude/commands/$md_name"
        echo "Linked: ~/.claude/commands/$md_name"
    elif [[ ${#md_files[@]} -gt 1 ]]; then
        # Multiple .md files: symlink the tool folder to ~/.claude/commands/<folder-name>/
        ln -sfn "$tool_dir" "$HOME/.claude/commands/$tool_name"
        echo "Linked: ~/.claude/commands/$tool_name/"
    fi

    echo "Deployed: $tool_name"
done

echo ""
echo "Done. Ensure ~/.local/bin is on your PATH."
