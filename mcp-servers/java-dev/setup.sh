#!/usr/bin/env bash
# setup.sh - Start Java dev MCP servers and configure Claude Code
#
# Usage:
#   ./setup.sh                  # Interactive: prompts for scope
#   ./setup.sh --global         # Add MCP config at user scope (all projects)
#   ./setup.sh --project /path  # Add MCP config at project scope
#   ./setup.sh --down           # Stop compose stack and remove MCP config
#   ./setup.sh --status         # Show compose and MCP server status
#
# What it does:
#   1. Starts the docker compose stack (maven-indexer + maven-tools)
#   2. Waits for maven-tools HTTP endpoint to be healthy
#   3. Adds MCP server entries to Claude Code via `claude mcp add`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Server names used in claude mcp config
INDEXER_NAME="maven-indexer"
TOOLS_NAME="maven-tools"

TOOLS_PORT=8090
HEALTH_TIMEOUT=30

# ── Helpers ──────────────────────────────────────────────────────────────────

die()  { echo "Error: $1" >&2; exit 1; }
info() { echo "==> $1"; }
warn() { echo "Warning: $1" >&2; }

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

# ── Compose helpers ──────────────────────────────────────────────────────────

compose_up() {
    info "Starting docker compose stack..."
    docker compose -f "$COMPOSE_FILE" up -d

    info "Waiting for maven-tools HTTP endpoint (port $TOOLS_PORT)..."
    local elapsed=0
    while ! curl -sf "http://127.0.0.1:$TOOLS_PORT/actuator/health" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [[ $elapsed -ge $HEALTH_TIMEOUT ]]; then
            warn "maven-tools did not become healthy within ${HEALTH_TIMEOUT}s"
            warn "It may still be starting. Check: docker compose -f $COMPOSE_FILE logs maven-tools"
            break
        fi
    done

    if [[ $elapsed -lt $HEALTH_TIMEOUT ]]; then
        info "maven-tools is healthy"
    fi

    info "Compose stack is up. Checking maven-indexer logs..."
    docker compose -f "$COMPOSE_FILE" logs --tail=5 maven-indexer
    echo ""
}

compose_down() {
    info "Stopping docker compose stack..."
    docker compose -f "$COMPOSE_FILE" down
}

# ── Claude Code MCP config ──────────────────────────────────────────────────

add_mcp_config() {
    local scope_flag="$1"

    info "Adding MCP servers to Claude Code ($scope_flag)..."

    # Remove existing entries first (ignore errors if they don't exist)
    claude_mcp remove "$INDEXER_NAME" 2>/dev/null || true
    claude_mcp remove "$TOOLS_NAME" 2>/dev/null || true

    # maven-indexer: STDIO via docker exec
    claude_mcp add \
        $scope_flag \
        --transport stdio \
        "$INDEXER_NAME" \
        -- docker exec -i mcp-maven-indexer npx -y maven-indexer-mcp@latest

    # maven-tools: SSE on localhost
    claude_mcp add \
        $scope_flag \
        --transport sse \
        "$TOOLS_NAME" \
        "http://127.0.0.1:$TOOLS_PORT/sse"

    info "MCP servers configured. Verify with: claude mcp list"
}

remove_mcp_config() {
    info "Removing MCP server entries from Claude Code..."

    if [[ -n "${PROJECT_DIR:-}" ]]; then
        # For project scope, remove entries from .mcp.json directly
        local mcp_file="$PROJECT_DIR/.mcp.json"
        if [[ -f "$mcp_file" ]]; then
            # Remove our server entries; delete file if empty
            local updated
            updated=$(python3 -c "
import json, sys
with open('$mcp_file') as f:
    data = json.load(f)
servers = data.get('mcpServers', {})
servers.pop('$INDEXER_NAME', None)
servers.pop('$TOOLS_NAME', None)
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
                info "Removed entries from $mcp_file"
            fi
        else
            info "No .mcp.json found in $PROJECT_DIR"
        fi
    else
        # For user scope, use claude mcp remove
        claude_mcp remove "$INDEXER_NAME" 2>/dev/null && info "Removed $INDEXER_NAME" || true
        claude_mcp remove "$TOOLS_NAME" 2>/dev/null && info "Removed $TOOLS_NAME" || true
    fi
}

# ── Scope resolution ────────────────────────────────────────────────────────

resolve_scope() {
    # Returns the claude mcp add scope flag(s)
    if [[ -n "${PROJECT_DIR:-}" ]]; then
        # Project scope writes to .mcp.json in the project root
        # We need to cd there for claude mcp add --scope project to find it
        if [[ ! -d "$PROJECT_DIR" ]]; then
            die "Project directory does not exist: $PROJECT_DIR"
        fi
        echo "--scope project"
    elif [[ "${GLOBAL:-false}" == "true" ]]; then
        echo "--scope user"
    else
        # Interactive prompt
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
    echo "── Docker Compose ──"
    docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || echo "Stack not running"
    echo ""

    echo "── maven-tools health ──"
    if curl -sf "http://127.0.0.1:$TOOLS_PORT/actuator/health" 2>/dev/null; then
        echo ""
        echo "Healthy"
    else
        echo "Not responding on port $TOOLS_PORT"
    fi
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
require_cmd curl
require_cmd claude

case "$ACTION" in
    up)
        compose_up

        scope_flag="$(resolve_scope)"

        if [[ -n "${PROJECT_DIR:-}" ]]; then
            # Run claude mcp add from the project directory so --scope project
            # writes to the right .mcp.json
            (cd "$PROJECT_DIR" && add_mcp_config "$scope_flag")
        else
            add_mcp_config "$scope_flag"
        fi

        echo ""
        info "Setup complete. Start Claude Code in your project to use the servers."
        info "Tools available:"
        echo "  maven-indexer: search_classes, get_class_details, search_artifacts,"
        echo "                 search_implementations, refresh_index"
        echo "  maven-tools:   get_latest_version, check_version_exists,"
        echo "                 compare_dependency_versions, analyze_project_health, ..."
        ;;
    down)
        remove_mcp_config
        compose_down
        info "Teardown complete."
        ;;
    status)
        show_status
        ;;
esac
