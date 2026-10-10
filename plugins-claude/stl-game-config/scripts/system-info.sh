#!/bin/bash
# system-info.sh - Detect system capabilities for STL game configuration
# Outputs JSON with system info for template selection

set -e

# sysfs DRM root; overridable so tests can supply fixture cards
DRM_ROOT="${STL_DRM_ROOT:-/sys/class/drm}"

# Map a PCI vendor ID to a vendor name; empty for anything else
vendor_name() {
  case "$1" in
    0x10de) echo "nvidia" ;;
    0x1002) echo "amd" ;;
    0x8086) echo "intel" ;;
  esac
}

# Detect the vendor of the GPU used for gaming. Vulkan labels each device as
# discrete or integrated, so prefer the first discrete GPU, then the first
# integrated one (software renderers such as llvmpipe are ignored). card0 is
# often the CPU's iGPU, so it is never assumed to be the gaming GPU.
detect_gpu_vendor() {
  local devices type t id vendor card best_score=0 best="" score
  if command -v vulkaninfo &>/dev/null; then
    # One "<deviceType> <vendorID>" line per GPU in the summary; the timeout
    # keeps a hung ICD from blocking the whole report
    devices=$(timeout 10 vulkaninfo --summary 2>/dev/null | awk '
      /^GPU[0-9]+:/ { if (t) print t, v; t = v = "" }
      /^[[:space:]]+vendorID[[:space:]]*=/ { v = $3 }
      /^[[:space:]]+deviceType[[:space:]]*=/ { t = $3 }
      END { if (t) print t, v }')
    for type in PHYSICAL_DEVICE_TYPE_DISCRETE_GPU PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU; do
      while read -r t id; do
        [ "$t" = "$type" ] || continue
        vendor=$(vendor_name "$id")
        if [ -n "$vendor" ]; then
          echo "$vendor"
          return
        fi
      done <<<"$devices"
    done
  fi

  # Fallback without Vulkan: rank sysfs DRM cards by vendor, NVIDIA > AMD >
  # Intel (sysfs has no discrete/integrated flag)
  for card in "$DRM_ROOT"/card[0-9]*; do
    # Skip connector entries such as card0-DP-1
    [[ "$(basename "$card")" =~ ^card[0-9]+$ ]] || continue
    vendor=$(vendor_name "$(cat "$card/device/vendor" 2>/dev/null)")
    case "$vendor" in
      nvidia) score=3 ;;
      amd) score=2 ;;
      intel) score=1 ;;
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
