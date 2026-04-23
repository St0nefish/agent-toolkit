#!/bin/bash
# generate-stl-config.sh - Generate STL per-game config from detection results
# Usage: generate-stl-config.sh <system-info-json> <game-api> <game-hdr> <app-id> <game-name>

set -e

SYSTEM_INFO="$1"
GAME_API="$2"        # dx12-rt, dx12, dx11, dx9
GAME_HDR="$3"        # true/false
APPID="$4"
GAME_NAME="$5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/../templates"

# Parse system info
GPU_VENDOR=$(echo "$SYSTEM_INFO" | jq -r '.gpu_vendor')
KDE_HDR_ENABLED=$(echo "$SYSTEM_INFO" | jq -r '.kde_hdr_enabled')

# Start with base template
cat "$TEMPLATES_DIR/base.conf"

echo ""
echo "# === GPU Settings (${GPU_VENDOR}) ==="

# GPU settings - use grep to extract the right section
case "$GPU_VENDOR" in
    nvidia)
        awk '/^# === NVIDIA ===$/{flag=1;next} /^# === AMD ===$/{flag=0} flag' "$TEMPLATES_DIR/gpu.conf" | sed 's/^# //' | grep -v "^$"
        ;;
    amd)
        awk '/^# === AMD ===$/{flag=1;next} /^# === Intel ===$/{flag=0} flag' "$TEMPLATES_DIR/gpu.conf" | sed 's/^# //' | grep -v "^$"
        ;;
    intel)
        awk '/^# === Intel ===$/{flag=1;next} /^# === Critical Notes ===$/{flag=0} flag' "$TEMPLATES_DIR/gpu.conf" | sed 's/^# //' | grep -v "^$"
        ;;
esac

echo ""
echo "# === API Settings (${GAME_API}) ==="

case "$GAME_API" in
    dx12-rt)
        awk '/^# === DX12 \+ Ray Tracing ===$/{flag=1;next} /^# === DX12 \(no RT\) ===$/{flag=0} flag' "$TEMPLATES_DIR/api.conf" | sed 's/^# //' | grep -v "^$"
        ;;
    dx12)
        awk '/^# === DX12 \(no RT\) ===$/{flag=1;next} /^# === DX11 \/ Vulkan ===$/{flag=0} flag' "$TEMPLATES_DIR/api.conf" | sed 's/^# //' | grep -v "^$"
        ;;
    dx11)
        awk '/^# === DX11 \/ Vulkan ===$/{flag=1;next} /^# === DX9 \(Retro\) ===$/{flag=0} flag' "$TEMPLATES_DIR/api.conf" | sed 's/^# //' | grep -v "^$"
        ;;
    dx9)
        awk '/^# === DX9 \(Retro\) ===$/{flag=1;next} /^# === Critical Notes ===$/{flag=0} flag' "$TEMPLATES_DIR/api.conf" | sed 's/^# //' | grep -v "^$"
        ;;
esac

# HDR settings (only if KDE HDR enabled AND game supports HDR)
if [[ "$KDE_HDR_ENABLED" == "true" ]] && [[ "$GAME_HDR" == "true" ]]; then
    echo ""
    echo "# === HDR Settings ==="
    case "$GAME_API" in
        dx12-rt|dx12)
            awk '/^# === HDR via Proton \(DX12 games\) ===$/{flag=1;next} /^# === HDR via DXVK \(DX11 games\) ===$/{flag=0} flag' "$TEMPLATES_DIR/hdr.conf" | sed 's/^# //' | grep -v "^$"
            ;;
        dx11)
            awk '/^# === HDR via DXVK \(DX11 games\) ===$/{flag=1;next} /^# === KDE HDR Prerequisites$/{flag=0} flag' "$TEMPLATES_DIR/hdr.conf" | sed 's/^# //' | grep -v "^$"
            ;;
    esac
fi

echo ""
echo "# Custom Variables for customvars/${APPID}.conf"
awk '/^# Custom Variables/,/^$/' "$TEMPLATES_DIR/customvars.conf" | sed 's/^# //' | sed "s/{APPID}/$APPID/g"