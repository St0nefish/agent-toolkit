#!/usr/bin/env bash
# setup.sh - Start/stop maven-indexer Docker Compose stack
#
# Usage:
#   ./setup.sh              # Start the compose stack
#   ./setup.sh --teardown   # Stop stack and remove containers/volumes
#
# MCP config registration is handled by deploy.py via deploy.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}/docker-compose.yml"

die()  { echo "Error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"
}

require_cmd docker

case "${1:-}" in
    --teardown)
        info "Stopping maven-indexer compose stack..."
        docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null \
            && info "Stack stopped and volumes removed" \
            || info "Stack was not running"
        ;;
    "")
        info "Starting maven-indexer compose stack..."
        docker compose -f "$COMPOSE_FILE" up -d
        info "Compose stack is up."
        docker compose -f "$COMPOSE_FILE" logs --tail=5 maven-indexer
        ;;
    *)
        die "Unknown option: $1 (use --teardown or no args)"
        ;;
esac
