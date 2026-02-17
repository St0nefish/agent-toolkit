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

# CLAUDE_CONFIG_DIR overrides ~/.claude for testing (e.g., point to /tmp/test-claude)
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

PROJECT_PATH=""
CLI_ON_PATH=false
DRY_RUN=false
SKIP_PERMISSIONS=false
INCLUDE=""
EXCLUDE=""
DEPLOYED_CONFIGS=()  # Collected resolved configs for permission management

# Run a command (with trace), or print it if --dry-run is active
run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "> $*"
        return 0
    fi
    set -x
    "$@"
    { set +x; } 2>/dev/null
}

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
  --dry-run              Show what would be done without making any changes
  --skip-permissions     Skip settings.json permission management
  -h, --help             Show this help message

--include and --exclude are mutually exclusive. Tool names match directory
names under tools/ (e.g., jar-explore, docker-pg-query).

CLI flags override config file values. Per-tool config is read from JSON
files (see CLAUDE.md for details):
  deploy.json / deploy.local.json          (repo-wide)
  tools/<name>/deploy.json / .local.json   (per-tool)

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
    [[ -L "$CLAUDE_CONFIG_DIR/commands/$md_name" ]] || [[ -L "$CLAUDE_CONFIG_DIR/$tool_name/$md_name" ]]
}

# Resolve deployment config for a tool by merging config layers (lowest → highest):
#   1. Hardcoded defaults
#   2. Repo-root deploy.json
#   3. Repo-root deploy.local.json
#   4. Tool-level deploy.json
#   5. Tool-level deploy.local.json
# Outputs merged JSON to stdout.
resolve_config() {
    local tool_dir="$1"
    local defaults='{"enabled":true,"scope":"global","on_path":false}'
    local layers=("$defaults")

    [[ -f "$SCRIPT_DIR/deploy.json" ]] && layers+=("$(cat "$SCRIPT_DIR/deploy.json")")
    [[ -f "$SCRIPT_DIR/deploy.local.json" ]] && layers+=("$(cat "$SCRIPT_DIR/deploy.local.json")")
    [[ -f "$tool_dir/deploy.json" ]] && layers+=("$(cat "$tool_dir/deploy.json")")
    [[ -f "$tool_dir/deploy.local.json" ]] && layers+=("$(cat "$tool_dir/deploy.local.json")")

    printf '%s\n' "${layers[@]}" | jq -s 'reduce .[] as $layer ({}; . * $layer)'
}

# Collect tool/hook-level config files for permission gathering.
# Repo-root configs are added once at startup; this adds only the item-specific files.
collect_config_permissions() {
    local item_dir="$1"
    [[ -f "$item_dir/deploy.json" ]] && DEPLOYED_CONFIGS+=("$item_dir/deploy.json")
    [[ -f "$item_dir/deploy.local.json" ]] && DEPLOYED_CONFIGS+=("$item_dir/deploy.local.json")
    return 0
}

# Gather all permissions from collected config files, deduplicate, and merge into settings.json
update_settings_permissions() {
    if [[ "$SKIP_PERMISSIONS" == true ]]; then
        echo "Skipped: permissions management (--skip-permissions)"
        return 0
    fi

    # Collect unique config files (repo-root files may be added multiple times)
    local -a unique_files=()
    local -A seen_files=()
    for f in "${DEPLOYED_CONFIGS[@]}"; do
        if [[ -z "${seen_files[$f]:-}" ]]; then
            seen_files[$f]=1
            unique_files+=("$f")
        fi
    done

    # Extract all permission entries from all config files
    local all_allows="" all_denies=""
    for f in "${unique_files[@]}"; do
        local allows denies
        allows=$(jq -r '.permissions.allow[]? // empty' "$f" 2>/dev/null) || true
        denies=$(jq -r '.permissions.deny[]? // empty' "$f" 2>/dev/null) || true
        [[ -n "$allows" ]] && all_allows+="$allows"$'\n'
        [[ -n "$denies" ]] && all_denies+="$denies"$'\n'
    done

    # Deduplicate and sort, then convert to JSON arrays
    local allows_json denies_json
    if [[ -n "$all_allows" ]]; then
        allows_json=$(printf '%s' "$all_allows" | grep -v '^$' | sort -u | jq -R . | jq -s .)
    else
        allows_json='[]'
    fi
    if [[ -n "$all_denies" ]]; then
        denies_json=$(printf '%s' "$all_denies" | grep -v '^$' | sort -u | jq -R . | jq -s .)
    else
        denies_json='[]'
    fi

    # Determine target settings file
    local settings_file="$CLAUDE_CONFIG_DIR/settings.json"
    if [[ -n "$PROJECT_PATH" ]]; then
        settings_file="$PROJECT_PATH/.claude/settings.json"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        local count
        count=$(echo "$allows_json" | jq 'length')
        echo "> Would update $settings_file permissions ($count allow entries)"
        return 0
    fi

    # Read existing settings or start with empty object
    local existing
    existing=$(cat "$settings_file" 2>/dev/null || echo '{}')

    # Merge permissions into settings, preserving all other keys
    echo "$existing" | jq \
        --argjson allows "$allows_json" \
        --argjson denies "$denies_json" \
        '.permissions.allow = $allows | .permissions.deny = $denies' \
        > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

    local count
    count=$(echo "$allows_json" | jq 'length')
    echo "Updated: $settings_file permissions ($count allow entries)"
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
            CLI_ON_PATH=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-permissions)
            SKIP_PERMISSIONS=true
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

if [[ -n "$PROJECT_PATH" && "$CLI_ON_PATH" == true ]]; then
    echo "Error: --on-path is not supported with --project" >&2
    exit 1
fi

if [[ -n "$INCLUDE" && -n "$EXCLUDE" ]]; then
    echo "Error: --include and --exclude are mutually exclusive" >&2
    exit 1
fi

if [[ -n "$PROJECT_PATH" && ! -d "$PROJECT_PATH" ]]; then
    echo "Error: Project directory does not exist: $PROJECT_PATH" >&2
    exit 1
fi

GLOBAL_COMMANDS_BASE="$CLAUDE_CONFIG_DIR/commands"
TOOLS_BASE="$CLAUDE_CONFIG_DIR/tools"

if [[ "$DRY_RUN" == true ]]; then
    echo "=== DRY RUN (no changes will be made) ==="
    echo ""
fi

run mkdir -p "$GLOBAL_COMMANDS_BASE"
run mkdir -p "$TOOLS_BASE"

# Always collect repo-root config files for permission management
[[ -f "$SCRIPT_DIR/deploy.json" ]] && DEPLOYED_CONFIGS+=("$SCRIPT_DIR/deploy.json")
[[ -f "$SCRIPT_DIR/deploy.local.json" ]] && DEPLOYED_CONFIGS+=("$SCRIPT_DIR/deploy.local.json")

if [[ ! -d "$TOOLS_DIR" ]]; then
    echo "No tools/ directory found."
    update_settings_permissions
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

    # --- Resolve deployment config ---
    config="$(resolve_config "$tool_dir")"
    cfg_enabled="$(echo "$config" | jq -r '.enabled')"
    cfg_scope="$(echo "$config" | jq -r '.scope')"
    cfg_on_path="$(echo "$config" | jq -r '.on_path')"

    if [[ "$cfg_enabled" == "false" ]]; then
        echo "Skipped: $tool_name (disabled by config)"
        continue
    fi

    # Determine effective scope: CLI --project overrides config
    if [[ -n "$PROJECT_PATH" ]]; then
        effective_scope="project"
    elif [[ "$cfg_scope" == "project" ]]; then
        echo "Skipped: $tool_name (scope=project, no --project flag given)"
        continue
    else
        effective_scope="global"
    fi

    # Determine effective on_path: CLI --on-path overrides config
    effective_on_path="$cfg_on_path"
    if [[ "$CLI_ON_PATH" == true ]]; then
        effective_on_path=true
    fi

    # Determine commands base for this tool's scope
    if [[ "$effective_scope" == "project" ]]; then
        COMMANDS_BASE="$PROJECT_PATH/.claude/commands"
    else
        COMMANDS_BASE="$GLOBAL_COMMANDS_BASE"
    fi
    run mkdir -p "$COMMANDS_BASE"

    # --- Deploy scripts: symlink tool directory to ~/.claude/tools/<tool-name> ---
    run ln -sfn "$tool_dir" "$TOOLS_BASE/$tool_name"
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
        if [[ "$effective_scope" == "project" ]] && is_globally_deployed "${md_files[0]}"; then
            echo "Skipped: $tool_name skill (already deployed globally)"
        else
            run ln -sf "${md_files[0]}" "$COMMANDS_BASE/$md_name"
            echo "Linked: $COMMANDS_BASE/$md_name"
        fi
    elif [[ ${#md_files[@]} -gt 1 ]]; then
        # Multiple skills: create subdirectory and symlink each
        local_skip_count=0
        if [[ "$effective_scope" == "project" ]]; then
            for md in "${md_files[@]}"; do
                if is_globally_deployed "$md"; then
                    ((local_skip_count++))
                fi
            done
        fi
        if [[ "$effective_scope" == "project" && "$local_skip_count" -eq ${#md_files[@]} ]]; then
            echo "Skipped: $tool_name skills (already deployed globally)"
        else
            run mkdir -p "$COMMANDS_BASE/$tool_name"
            for md in "${md_files[@]}"; do
                md_name="$(basename "$md")"
                if [[ "$effective_scope" == "project" ]] && is_globally_deployed "$md"; then
                    echo "Skipped: $tool_name/$md_name (already deployed globally)"
                else
                    run ln -sf "$md" "$COMMANDS_BASE/$tool_name/$md_name"
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
            run rm "$old_link"
            echo "Cleaned: stale directory symlink $old_link"
        fi
    fi

    # --- Optionally symlink scripts to ~/.local/bin/ ---
    if [[ "$effective_on_path" == "true" ]] && [[ -d "$tool_dir/bin" ]]; then
        run mkdir -p "$HOME/.local/bin"
        for script in "$tool_dir"/bin/*; do
            [[ -f "$script" ]] || continue
            script_name="$(basename "$script")"
            run ln -sf "$script" "$HOME/.local/bin/$script_name"
            echo "Linked: ~/.local/bin/$script_name"
        done
    fi

    # --- Collect permissions from this tool's config chain ---
    collect_config_permissions "$tool_dir"

    echo "Deployed: $tool_name"
done

# ===== Deploy hooks =====
HOOKS_BASE="$CLAUDE_CONFIG_DIR/hooks"

if [[ -d "$HOOKS_DIR" ]]; then
    run mkdir -p "$HOOKS_BASE"
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

        # Check config for enabled flag (hooks only use enabled)
        config="$(resolve_config "$hook_dir")"
        cfg_enabled="$(echo "$config" | jq -r '.enabled')"
        if [[ "$cfg_enabled" == "false" ]]; then
            echo "Skipped: hook $hook_name (disabled by config)"
            continue
        fi

        run ln -sfn "$hook_dir" "$HOOKS_BASE/$hook_name"
        echo "Linked: ~/.claude/hooks/$hook_name"

        # --- Collect permissions from this hook's config chain ---
        collect_config_permissions "$hook_dir"

        echo "Deployed: hook $hook_name"
    done
fi

# ===== Manage settings.json permissions =====
echo ""
update_settings_permissions

echo ""
if [[ -n "$PROJECT_PATH" ]]; then
    echo "Deployed to: $PROJECT_PATH/.claude/commands (project skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
else
    echo "Deployed to: ~/.claude/commands (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
fi
if [[ "$CLI_ON_PATH" == true ]]; then
    echo "Scripts also linked to: ~/.local/bin (via --on-path flag)"
fi
