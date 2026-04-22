#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

ACTION="${1:-}"

cd "$PLUGIN_ROOT"

case "$ACTION" in
    --teardown)
        docker compose down -v
        ;;
    *)
        docker compose up -d
        ;;
esac