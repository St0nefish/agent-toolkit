#!/usr/bin/env bash
# setup.sh - Pull maven-tools image and configure Claude Code
#
# Usage:
#   ./setup.sh                  # Interactive: prompts for scope
#   ./setup.sh --global         # Add MCP config at user scope (all projects)
#   ./setup.sh --project /path  # Add MCP config at project scope
#   ./setup.sh --down           # Remove MCP config
#   ./setup.sh --status         # Show MCP server status
#
# What it does:
#   1. Pulls the maven-tools-mcp Docker image
#   2. Adds the MCP server entry to Claude Code via `claude mcp add`
#
# maven-tools runs on demand via `docker run --rm -i` (no compose needed).

set -euo pipefail

SERVER_NAME="maven-tools"
IMAGE="arvindand/maven-tools-mcp:2.0.2-noc7"

# ── Helpers ──────────────────────────────────────────────────────────────────

die()  { echo "Error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

usage() {
    sed -n '2,/^$/{ s/^# \?//; p }' "$0"
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"
}

# claude mcp add refuses to run inside a Claude Code session.
# Unset the guard variable so it works when invoked from Claude Code.
claude_mcp() {
    env -u CLAUDECODE claude mcp "$@"
}

# ── Claude Code MCP config ──────────────────────────────────────────────────

add_mcp_config() {
    local scope_flag="$1"

    info "Adding maven-tools to Claude Code ($scope_flag)..."

    # Remove existing entry first (ignore errors if it doesn't exist)
    claude_mcp remove "$SERVER_NAME" 2>/dev/null || true

    # maven-tools: STDIO via docker run --rm -i
    claude_mcp add \
        $scope_flag \
        --transport stdio \
        "$SERVER_NAME" \
        -- docker run --rm -i "$IMAGE"

    info "MCP server configured. Verify with: claude mcp list"
}

remove_mcp_config() {
    info "Removing MCP server entry from Claude Code..."

    if [[ -n "${PROJECT_DIR:-}" ]]; then
        local mcp_file="$PROJECT_DIR/.mcp.json"
        if [[ -f "$mcp_file" ]]; then
            local updated
            updated=$(python3 -c "
import json, sys
with open('$mcp_file') as f:
    data = json.load(f)
servers = data.get('mcpServers', {})
servers.pop('$SERVER_NAME', None)
if servers:
    data['mcpServers'] = servers
    print(json.dumps(data, indent=2))
else:
    print('')
" 2>/dev/null) || true

            if [[ -z "$updated" ]]; then
                rm -f "$mcp_file"
                info "Removed $mcp_file (no servers left)"
            else
                echo "$updated" > "$mcp_file"
                info "Removed entry from $mcp_file"
            fi
        else
            info "No .mcp.json found in $PROJECT_DIR"
        fi
    else
        claude_mcp remove "$SERVER_NAME" 2>/dev/null && info "Removed $SERVER_NAME" || true
    fi
}

# ── Scope resolution ────────────────────────────────────────────────────────

resolve_scope() {
    if [[ -n "${PROJECT_DIR:-}" ]]; then
        if [[ ! -d "$PROJECT_DIR" ]]; then
            die "Project directory does not exist: $PROJECT_DIR"
        fi
        echo "--scope project"
    elif [[ "${GLOBAL:-false}" == "true" ]]; then
        echo "--scope user"
    else
        echo ""
        echo "Where should the MCP config be added?"
        echo ""
        echo "  1) Global (user scope) - available in all projects"
        echo "  2) Project - added to a specific project's .mcp.json"
        echo ""
        read -rp "Choice [1/2]: " choice

        case "$choice" in
            1)
                echo "--scope user"
                ;;
            2)
                read -rp "Project directory: " dir
                dir="${dir/#\~/$HOME}"
                if [[ ! -d "$dir" ]]; then
                    die "Directory does not exist: $dir"
                fi
                PROJECT_DIR="$dir"
                echo "--scope project"
                ;;
            *)
                die "Invalid choice: $choice"
                ;;
        esac
    fi
}

# ── Status ───────────────────────────────────────────────────────────────────

show_status() {
    echo "── Docker image ──"
    docker image inspect "$IMAGE" --format '{{.RepoTags}} ({{.Size}} bytes, created {{.Created}})' 2>/dev/null \
        || echo "Image not pulled: $IMAGE"
    echo ""

    echo "── Claude Code MCP servers ──"
    claude_mcp list 2>/dev/null || echo "Could not query Claude Code MCP config"
}

# ── Main ─────────────────────────────────────────────────────────────────────

ACTION="up"
GLOBAL=false
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --global|-g)
            GLOBAL=true
            shift
            ;;
        --project|-p)
            [[ $# -ge 2 ]] || die "--project requires a directory argument"
            PROJECT_DIR="${2/#\~/$HOME}"
            shift 2
            ;;
        --down|--remove)
            ACTION="down"
            shift
            ;;
        --status|-s)
            ACTION="status"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            die "Unknown option: $1 (try --help)"
            ;;
    esac
done

require_cmd docker
require_cmd claude

case "$ACTION" in
    up)
        info "Pulling maven-tools image..."
        docker pull "$IMAGE"

        scope_flag="$(resolve_scope)"

        if [[ -n "${PROJECT_DIR:-}" ]]; then
            (cd "$PROJECT_DIR" && add_mcp_config "$scope_flag")
        else
            add_mcp_config "$scope_flag"
        fi

        echo ""
        info "Setup complete. maven-tools runs on demand (no persistent container)."
        info "Tools available:"
        echo "  maven-tools: get_latest_version, check_version_exists,"
        echo "               compare_dependency_versions, analyze_project_health, ..."
        ;;
    down)
        remove_mcp_config
        info "Teardown complete."
        ;;
    status)
        show_status
        ;;
esac
