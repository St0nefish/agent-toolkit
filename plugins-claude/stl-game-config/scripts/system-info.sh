#!/bin/bash
# system-info.sh - Detect system capabilities for STL game configuration
# Outputs JSON with system info for template selection

set -e

# sysfs DRM root; overridable so tests can supply fixture cards
DRM_ROOT="${STL_DRM_ROOT:-/sys/class/drm}"

# Detect the vendor of the GPU used for gaming. card0 is often the CPU's iGPU
# (e.g. Ryzen iGPU as card0, discrete NVIDIA as card1), so rank every card:
# NVIDIA > discrete AMD > Intel > AMD iGPU. An amdgpu device with under 2 GiB
# of VRAM is treated as an iGPU (its VRAM is a small BIOS carve-out).
detect_gpu_vendor() {
  local card vendor vram score best_score=0 best=""
  for card in "$DRM_ROOT"/card[0-9]*; do
    # Skip connector entries such as card0-DP-1
    [[ "$(basename "$card")" =~ ^card[0-9]+$ ]] || continue
    vendor=$(cat "$card/device/vendor" 2>/dev/null) || continue
    case "$vendor" in
      0x10de) score=4 vendor=nvidia ;;
      0x1002)
        vram=$(cat "$card/device/mem_info_vram_total" 2>/dev/null) || vram=0
        if [ "${vram:-0}" -ge 2147483648 ]; then score=3; else score=1; fi
        vendor=amd
        ;;
      0x8086) score=2 vendor=intel ;;
      *) continue ;;
    esac
    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      best=$vendor
    fi
  done
  if [ -n "$best" ]; then
    echo "$best"
    return
  fi

  # Fallback: NVIDIA proprietary driver without nvidia-drm exposes no DRM card
  if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then
    echo "nvidia"
    return
  fi

  # Fallback: check Vulkan devices
  if command -v vulkaninfo &>/dev/null; then
    vulkaninfo --summary 2>/dev/null | grep -qi "NVIDIA" && echo "nvidia" && return
    vulkaninfo --summary 2>/dev/null | grep -qi "AMD" && echo "amd" && return
    vulkaninfo --summary 2>/dev/null | grep -qi "Intel" && echo "intel" && return
  fi
  echo "unknown"
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

  # Check if kscreen-doctor and jq are available
  if ! command -v kscreen-doctor &>/dev/null || ! command -v jq &>/dev/null; then
    echo "false"
    return
  fi

  # Primary output is the enabled one with priority 1. JSON output avoids the
  # ANSI color codes kscreen-doctor -o emits even through a pipe.
  local hdr
  hdr=$(kscreen-doctor -j 2>/dev/null |
    jq -r '[.outputs[]? | select(.enabled and .priority == 1)][0].hdr // false' 2>/dev/null) || true

  if [ "$hdr" = "true" ]; then
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
