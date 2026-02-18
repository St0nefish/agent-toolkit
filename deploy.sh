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
SKILLS_DIR="$SCRIPT_DIR/skills"
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
DEPLOYED_HOOK_CONFIGS=()  # Collected hook_name|config_path pairs for hooks management

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
names under skills/ (e.g., jar-explore, docker-pg-query).

CLI flags override config file values. Per-tool config is read from JSON
files (see CLAUDE.md for details):
  deploy.json / deploy.local.json          (repo-wide)
  skills/<name>/deploy.json / .local.json  (per-skill)

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

# Create a symlink from $target -> $link_path, skipping if already correct.
# Usage: ensure_link <link_path> <target> <label>
# - In dry-run mode: prints the command that would run
# - If symlink already points to target: prints "OK: <label>"
# - Otherwise: creates/overwrites the symlink and prints "Linked: <label>"
# Pass -n as $4 to use ln -sfn (for directories) instead of ln -sf.
ensure_link() {
    local link_path="$1" target="$2" label="$3" dir_flag="${4:-}"
    if [[ "$DRY_RUN" != true ]] && [[ -L "$link_path" ]] && [[ "$(readlink "$link_path")" == "$target" ]]; then
        echo "OK: $label"
        return 0
    fi
    if [[ "$dir_flag" == "-n" ]]; then
        run ln -sfn "$target" "$link_path"
    else
        run ln -sf "$target" "$link_path"
    fi
    echo "Linked: $label"
}

# Returns 0 (true = skip) if the tool should be filtered out by --include/--exclude
is_filtered_out() {
    local skill_name="$1"
    if [[ -n "$INCLUDE" ]]; then
        # Only deploy skills in the include list
        if [[ ",$INCLUDE," != *",$skill_name,"* ]]; then
            return 0
        fi
    elif [[ -n "$EXCLUDE" ]]; then
        # Skip skills in the exclude list
        if [[ ",$EXCLUDE," == *",$skill_name,"* ]]; then
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
    [[ -L "$CLAUDE_CONFIG_DIR/commands/$md_name" ]] || [[ -L "$CLAUDE_CONFIG_DIR/commands/$tool_name/$md_name" ]]
}

# Resolve deployment config for a tool by merging config layers (lowest → highest):
#   1. Hardcoded defaults
#   2. Repo-root deploy.json
#   3. Repo-root deploy.local.json
#   4. Tool-level deploy.json
#   5. Tool-level deploy.local.json
# Outputs merged JSON to stdout.
resolve_config() {
    local skill_dir="$1"
    local defaults='{"enabled":true,"scope":"global","on_path":false}'
    local layers=("$defaults")

    [[ -f "$SCRIPT_DIR/deploy.json" ]] && layers+=("$(cat "$SCRIPT_DIR/deploy.json")")
    [[ -f "$SCRIPT_DIR/deploy.local.json" ]] && layers+=("$(cat "$SCRIPT_DIR/deploy.local.json")")
    [[ -f "$skill_dir/deploy.json" ]] && layers+=("$(cat "$skill_dir/deploy.json")")
    [[ -f "$skill_dir/deploy.local.json" ]] && layers+=("$(cat "$skill_dir/deploy.local.json")")

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

    # Merge permissions into settings: union with existing, deduplicate, sort
    echo "$existing" | jq \
        --argjson allows "$allows_json" \
        --argjson denies "$denies_json" \
        '
        .permissions.allow = (((.permissions.allow // []) + $allows) | unique) |
        .permissions.deny = (((.permissions.deny // []) + $denies) | unique)
        ' \
        > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

    local count
    count=$(jq '.permissions.allow | length' "$settings_file")
    echo "Updated: $settings_file permissions ($count allow entries)"
}

# Build the hooks JSON object from collected hook configs and merge into settings.json
update_settings_hooks() {
    if [[ "$SKIP_PERMISSIONS" == true ]]; then
        echo "Skipped: hooks management (--skip-permissions)"
        return 0
    fi

    if [[ ${#DEPLOYED_HOOK_CONFIGS[@]} -eq 0 ]]; then
        return 0
    fi

    # Build hooks JSON grouped by event
    local hooks_json='{}'
    for entry in "${DEPLOYED_HOOK_CONFIGS[@]}"; do
        local hook_name="${entry%%|*}"
        local config_path="${entry#*|}"

        local event matcher command_script async_flag timeout_val
        event=$(jq -r '.hooks_config.event' "$config_path")
        matcher=$(jq -r '.hooks_config.matcher' "$config_path")
        command_script=$(jq -r '.hooks_config.command_script' "$config_path")
        async_flag=$(jq -r '.hooks_config.async // false' "$config_path")
        timeout_val=$(jq -r '.hooks_config.timeout // empty' "$config_path")

        # Resolve command path
        local command_path="$HOOKS_BASE/$hook_name/$command_script"

        # Build the hook entry
        local hook_entry
        hook_entry=$(jq -n --arg cmd "$command_path" '{type: "command", command: $cmd}')
        if [[ "$async_flag" == "true" ]]; then
            hook_entry=$(echo "$hook_entry" | jq '.async = true')
        fi
        if [[ -n "$timeout_val" ]]; then
            hook_entry=$(echo "$hook_entry" | jq --argjson t "$timeout_val" '.timeout = $t')
        fi

        # Build the matcher group entry
        local matcher_group
        matcher_group=$(jq -n --arg m "$matcher" --argjson h "[$hook_entry]" '{matcher: $m, hooks: $h}')

        # Append to the event array in hooks_json
        hooks_json=$(echo "$hooks_json" | jq \
            --arg event "$event" \
            --argjson group "$matcher_group" \
            '.[$event] = ((.[$event] // []) + [$group])')
    done

    # Determine target settings file (hooks always go to global)
    local settings_file="$CLAUDE_CONFIG_DIR/settings.json"

    if [[ "$DRY_RUN" == true ]]; then
        local event_count
        event_count=$(echo "$hooks_json" | jq 'keys | length')
        echo "> Would update $settings_file hooks ($event_count events)"
        return 0
    fi

    # Read existing settings or start with empty object
    local existing
    existing=$(cat "$settings_file" 2>/dev/null || echo '{}')

    # Merge hooks into settings: preserve existing event+matcher pairs, add missing ones
    echo "$existing" | jq \
        --argjson new_hooks "$hooks_json" \
        '
        reduce ($new_hooks | to_entries[]) as $evt (
            .;
            .hooks[$evt.key] = (
                reduce $evt.value[] as $group (
                    (.hooks[$evt.key] // []);
                    if any(.[]; .matcher == $group.matcher)
                    then .
                    else . + [$group]
                    end
                )
            )
        )
        ' \
        > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

    local event_count
    event_count=$(jq '.hooks | keys | length' "$settings_file")
    echo "Updated: $settings_file hooks ($event_count events)"
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

if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "No skills/ directory found."
    update_settings_permissions
    exit 0
fi

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_dir="${skill_dir%/}"
    skill_name="$(basename "$skill_dir")"

    if [[ -x "$skill_dir/condition.sh" ]]; then
        if ! "$skill_dir/condition.sh" >/dev/null 2>&1; then
            echo "Skipped: $skill_name (condition not met)"
            continue
        fi
    fi

    if is_filtered_out "$skill_name"; then
        echo "Skipped: $skill_name (filtered out)"
        continue
    fi

    # --- Resolve deployment config ---
    config="$(resolve_config "$skill_dir")"
    cfg_enabled="$(echo "$config" | jq -r '.enabled')"
    cfg_scope="$(echo "$config" | jq -r '.scope')"
    cfg_on_path="$(echo "$config" | jq -r '.on_path')"

    if [[ "$cfg_enabled" == "false" ]]; then
        echo "Skipped: $skill_name (disabled by config)"
        continue
    fi

    # Determine effective scope: CLI --project overrides config
    if [[ -n "$PROJECT_PATH" ]]; then
        effective_scope="project"
    elif [[ "$cfg_scope" == "project" ]]; then
        echo "Skipped: $skill_name (scope=project, no --project flag given)"
        continue
    else
        effective_scope="global"
    fi

    # Determine effective on_path: CLI --on-path overrides config
    effective_on_path="$cfg_on_path"
    if [[ "$CLI_ON_PATH" == true ]]; then
        effective_on_path=true
    fi

    # Determine commands base for this skill's scope
    if [[ "$effective_scope" == "project" ]]; then
        COMMANDS_BASE="$PROJECT_PATH/.claude/commands"
    else
        COMMANDS_BASE="$GLOBAL_COMMANDS_BASE"
    fi
    run mkdir -p "$COMMANDS_BASE"

    # --- Deploy scripts: symlink skill directory to ~/.claude/tools/<skill-name> ---
    ensure_link "$TOOLS_BASE/$skill_name" "$skill_dir" "~/.claude/tools/$skill_name" -n

    # --- Deploy skills: symlink .md files (excluding README.md) to commands ---
    md_files=()
    for md in "$skill_dir"/*.md; do
        [[ -f "$md" ]] || continue
        [[ "$(basename "$md")" == "README.md" ]] && continue
        md_files+=("$md")
    done

    if [[ ${#md_files[@]} -eq 1 ]]; then
        # Single skill: symlink directly as commands/<md-filename>
        md_name="$(basename "${md_files[0]}")"
        if [[ "$effective_scope" == "project" ]] && is_globally_deployed "${md_files[0]}"; then
            echo "Skipped: $skill_name skill (already deployed globally)"
        else
            ensure_link "$COMMANDS_BASE/$md_name" "${md_files[0]}" "$COMMANDS_BASE/$md_name"
        fi
    elif [[ ${#md_files[@]} -gt 1 ]]; then
        # Multiple skills: create subdirectory and symlink each
        local_skip_count=0
        if [[ "$effective_scope" == "project" ]]; then
            for md in "${md_files[@]}"; do
                if is_globally_deployed "$md"; then
                    local_skip_count=$((local_skip_count + 1))
                fi
            done
        fi
        if [[ "$effective_scope" == "project" && "$local_skip_count" -eq ${#md_files[@]} ]]; then
            echo "Skipped: $skill_name skills (already deployed globally)"
        else
            run mkdir -p "$COMMANDS_BASE/$skill_name"
            for md in "${md_files[@]}"; do
                md_name="$(basename "$md")"
                if [[ "$effective_scope" == "project" ]] && is_globally_deployed "$md"; then
                    echo "Skipped: $skill_name/$md_name (already deployed globally)"
                else
                    ensure_link "$COMMANDS_BASE/$skill_name/$md_name" "$md" "$COMMANDS_BASE/$skill_name/$md_name"
                fi
            done
        fi
    fi

    # --- Clean up stale old-style directory symlink if present ---
    # Old deploy.sh symlinked the entire skill dir to commands/<skill-name>.
    # If that symlink still exists and points to a skills/ source dir, remove it.
    old_link="$COMMANDS_BASE/$skill_name"
    if [[ -L "$old_link" && -d "$old_link" ]]; then
        link_target="$(readlink "$old_link")"
        if [[ "$link_target" == */skills/* ]]; then
            run rm "$old_link"
            echo "Cleaned: stale directory symlink $old_link"
        fi
    fi

    # --- Optionally symlink scripts to ~/.local/bin/ ---
    if [[ "$effective_on_path" == "true" ]] && [[ -d "$skill_dir/bin" ]]; then
        run mkdir -p "$HOME/.local/bin"
        for script in "$skill_dir"/bin/*; do
            [[ -f "$script" ]] || continue
            script_name="$(basename "$script")"
            ensure_link "$HOME/.local/bin/$script_name" "$script" "~/.local/bin/$script_name"
        done
    fi

    # --- Collect permissions from this skill's config chain ---
    collect_config_permissions "$skill_dir"

    # --- Deploy dependencies: symlink skill dirs + collect permissions, skip skills ---
    deps=$(echo "$config" | jq -r '.dependencies[]? // empty' 2>/dev/null) || true
    if [[ -n "$deps" ]]; then
        while IFS= read -r dep; do
            [[ -z "$dep" ]] && continue
            dep_dir="$SKILLS_DIR/$dep"
            if [[ ! -d "$dep_dir" ]]; then
                echo "Warning: dependency '$dep' not found (required by $skill_name)"
                continue
            fi
            ensure_link "$TOOLS_BASE/$dep" "$dep_dir" "~/.claude/tools/$dep (dependency of $skill_name)" -n
            collect_config_permissions "$dep_dir"
        done <<< "$deps"
    fi

    echo "Deployed: $skill_name"
done

# ===== Deploy hooks =====
HOOKS_BASE="$CLAUDE_CONFIG_DIR/hooks"

if [[ -d "$HOOKS_DIR" ]]; then
    run mkdir -p "$HOOKS_BASE"
    for hook_dir in "$HOOKS_DIR"/*/; do
        hook_dir="${hook_dir%/}"
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

        ensure_link "$HOOKS_BASE/$hook_name" "$hook_dir" "~/.claude/hooks/$hook_name" -n

        # --- Collect permissions from this hook's config chain ---
        collect_config_permissions "$hook_dir"

        # --- Collect hook config for settings.json hooks wiring ---
        if [[ -f "$hook_dir/deploy.json" ]] && jq -e '.hooks_config' "$hook_dir/deploy.json" >/dev/null 2>&1; then
            DEPLOYED_HOOK_CONFIGS+=("$hook_name|$hook_dir/deploy.json")
        fi

        echo "Deployed: hook $hook_name"
    done
fi

# ===== Manage settings.json permissions =====
echo ""
update_settings_permissions

# ===== Manage settings.json hooks =====
update_settings_hooks

echo ""
if [[ -n "$PROJECT_PATH" ]]; then
    echo "Deployed to: $PROJECT_PATH/.claude/commands (project skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
else
    echo "Deployed to: ~/.claude/commands (skills) + ~/.claude/tools (scripts) + ~/.claude/hooks (hooks)"
fi
if [[ "$CLI_ON_PATH" == true ]]; then
    echo "Scripts also linked to: ~/.local/bin (via --on-path flag)"
fi
