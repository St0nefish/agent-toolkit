#!/bin/bash
# install-templates.sh - Install templates to STL config directory
# Usage: install-templates.sh [template-name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"
STL_CONFIG_DIR="$HOME/.config/steamtinkerlaunch"

if [[ ! -d "$STL_CONFIG_DIR" ]]; then
    echo "Error: STL config directory not found at $STL_CONFIG_DIR"
    echo "Please install SteamTinkerLaunch first."
    exit 1
fi

if [[ -n "$1" ]]; then
    # Install specific template
    TEMPLATE="$1"
    if [[ ! -f "$TEMPLATES_DIR/$TEMPLATE.conf" ]]; then
        echo "Error: Template '$TEMPLATE' not found"
        exit 1
    fi
    
    case "$TEMPLATE" in
        base)
            echo "Installing base settings to default_template.conf"
            cp "$TEMPLATES_DIR/base.conf" "$STL_CONFIG_DIR/default_template.conf"
            ;;
        gpu)
            echo "GPU template requires system detection first"
            echo "Use the stl-game-config skill instead"
            ;;
        api)
            echo "API template requires game detection first"
            echo "Use the stl-game-config skill instead"
            ;;
        hdr)
            echo "HDR template requires KDE HDR detection first"
            echo "Use the stl-game-config skill instead"
            ;;
        customvars)
            echo "Customvars template requires AppID"
            echo "Use the stl-game-config skill instead"
            ;;
        *)
            echo "Unknown template: $TEMPLATE"
            exit 1
            ;;
    esac
else
    # Install all templates
    echo "Installing all STL templates..."
    cp "$TEMPLATES_DIR/base.conf" "$STL_CONFIG_DIR/default_template.conf"
    cp "$TEMPLATES_DIR/gpu.conf" "$STL_CONFIG_DIR/gpu_template.conf"
    cp "$TEMPLATES_DIR/api.conf" "$STL_CONFIG_DIR/api_template.conf"
    cp "$TEMPLATES_DIR/hdr.conf" "$STL_CONFIG_DIR/hdr_template.conf"
    cp "$TEMPLATES_DIR/customvars.conf" "$STL_CONFIG_DIR/customvars_template.conf"
    echo "Templates installed to $STL_CONFIG_DIR"
fi