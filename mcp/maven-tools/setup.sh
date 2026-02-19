#!/usr/bin/env bash
# setup.sh - Pull maven-tools Docker image
#
# Usage:
#   ./setup.sh              # Pull the image
#   ./setup.sh --teardown   # Remove the image
#
# MCP config registration is handled by deploy.py via deploy.json.

set -euo pipefail

IMAGE="arvindand/maven-tools-mcp:2.0.2-noc7"

die()  { echo "Error: $1" >&2; exit 1; }
info() { echo "==> $1"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"
}

require_cmd docker

case "${1:-}" in
    --teardown)
        info "Removing maven-tools image..."
        docker rmi "$IMAGE" 2>/dev/null && info "Removed $IMAGE" || info "Image not found: $IMAGE"
        ;;
    "")
        info "Pulling maven-tools image..."
        docker pull "$IMAGE"
        info "Setup complete. maven-tools runs on demand (no persistent container)."
        ;;
    *)
        die "Unknown option: $1 (use --teardown or no args)"
        ;;
esac
