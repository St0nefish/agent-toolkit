#!/bin/bash
# system-info.sh - Detect system capabilities for STL game configuration
# Outputs JSON with system info for template selection

set -e

# Detect GPU vendor
detect_gpu_vendor() {
    if command -v nvidia-smi &>/dev/null; then
        echo "nvidia"
    elif command -v amdgpu-pro-info &>/dev/null || ls /sys/class/drm/card0/device/vendor 2>/dev/null | grep -q "1002"; then
        echo "amd"
    elif ls /sys/class/drm/card0/device/vendor 2>/dev/null | grep -q "8086"; then
        echo "intel"
    else
        # Fallback: check Vulkan devices
        if command -v vulkaninfo &>/dev/null; then
            vulkaninfo --summary 2>/dev/null | grep -i "NVIDIA" && echo "nvidia" && return
            vulkaninfo --summary 2>/dev/null | grep -i "AMD" && echo "amd" && return
            vulkaninfo --summary 2>/dev/null | grep -i "Intel" && echo "intel" && return
        fi
        echo "unknown"
    fi
}

# Detect compositor/window manager
detect_compositor() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        case "$XDG_CURRENT_DESKTOP" in
            *KDE*) echo "kde" ;;
            *GNOME*) echo "gnome" ;;
            *XFCE*) echo "xfce" ;;
            *MATE*) echo "mate" ;;
            *) echo "other-wayland" ;;
        esac
    elif [ "$XDG_SESSION_TYPE" = "x11" ]; then
        case "$XDG_CURRENT_DESKTOP" in
            *KDE*) echo "kde-x11" ;;
            *GNOME*) echo "gnome-x11" ;;
            *) echo "other-x11" ;;
        esac
    else
        echo "unknown"
    fi
}

# Check if KDE HDR is enabled on primary monitor
check_kde_hdr_enabled() {
    if [ "$(detect_compositor)" != "kde" ]; then
        echo "false"
        return
    fi
    
    # Check if kscreen-doctor is available
    if ! command -v kscreen-doctor &>/dev/null; then
        echo "false"
        return
    fi
    
    # Get primary output and check HDR status
    local output
    output=$(kscreen-doctor -o 2>/dev/null | grep -E "HDR|DDC" | head -1)
    
    if echo "$output" | grep -q "HDR: enabled"; then
        echo "true"
    else
        echo "false"
    fi
}

# Main output
main() {
    cat <<EOF
{
  "gpu_vendor": "$(detect_gpu_vendor)",
  "compositor": "$(detect_compositor)",
  "kde_hdr_enabled": $(check_kde_hdr_enabled)
}
EOF
}

main