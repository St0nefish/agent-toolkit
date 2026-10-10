#!/usr/bin/env bash
# test-system-info.sh — assertions for check_kde_hdr_enabled and
# detect_gpu_vendor in system-info.sh.
# HDR: a PATH-injected kscreen-doctor mock prints fixture JSON for -j, so the
# result depends only on the fixture: HDR state of the primary (priority 1)
# enabled output, false on anything unparseable or non-KDE.
# GPU: a PATH-injected vulkaninfo mock prints fixture devices; STL_DRM_ROOT
# points at a fixture tree of cardN/device/vendor files for the fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../plugins-claude/stl-game-config/scripts/system-info.sh"

MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT
FIXTURE="$MOCK_DIR/kscreen.json"

cat >"$MOCK_DIR/kscreen-doctor" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-j" ] && cat "$FIXTURE"
EOF
chmod +x "$MOCK_DIR/kscreen-doctor"

PASS=0
FAIL=0

# assert_hdr <label> <want> <fixture-json> [desktop]
assert_hdr() {
  local label="$1" want="$2" fixture="$3" desktop="${4:-KDE}" got
  printf '%s' "$fixture" >"$FIXTURE"
  got=$(PATH="$MOCK_DIR:$PATH" XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP="$desktop" \
    bash "$SCRIPT" | jq -r '.kde_hdr_enabled')

  if [[ "$got" == "$want" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "      want: %s  got: %s\n" "$want" "$got"
    ((FAIL++)) || true
  fi
}

echo "── check_kde_hdr_enabled ──"
assert_hdr "non-HDR secondary listed first, primary HDR on (issue #182)" true \
  '{"outputs":[{"name":"DP-2","enabled":true,"priority":2},{"name":"DP-3","enabled":true,"priority":1,"hdr":true}]}'
assert_hdr "primary HDR off, secondary HDR on" false \
  '{"outputs":[{"name":"DP-2","enabled":true,"priority":2,"hdr":true},{"name":"DP-3","enabled":true,"priority":1,"hdr":false}]}'
assert_hdr "single output without hdr key" false \
  '{"outputs":[{"name":"DP-1","enabled":true,"priority":1}]}'
assert_hdr "disabled output carrying priority 1 is ignored" false \
  '{"outputs":[{"name":"DP-1","enabled":false,"priority":1,"hdr":true}]}'
assert_hdr "invalid JSON" false 'not json'
assert_hdr "empty output" false ''
assert_hdr "non-KDE compositor" false \
  '{"outputs":[{"name":"DP-1","enabled":true,"priority":1,"hdr":true}]}' GNOME

# vulkaninfo mock: prints a --summary device list built from VULKAN_DEVICES
# ("TYPE:vendorID ...", e.g. "INTEGRATED_GPU:0x1002 DISCRETE_GPU:0x10de"),
# nothing when unset. nvidia-smi mock lists no GPU unless NVIDIA_SMI_GPUS=1.
cat >"$MOCK_DIR/vulkaninfo" <<'EOF'
#!/usr/bin/env bash
[ -n "${VULKAN_DEVICES:-}" ] || exit 0
printf 'Devices:\n========\n'
i=0
for d in $VULKAN_DEVICES; do
  printf 'GPU%d:\n' "$i"
  printf '\tvendorID           = %s\n' "${d#*:}"
  printf '\tdeviceType         = PHYSICAL_DEVICE_TYPE_%s\n' "${d%%:*}"
  printf '\tdeviceName         = mock device %d\n' "$i"
  i=$((i + 1))
done
EOF
printf '#!/usr/bin/env bash\n[ "${NVIDIA_SMI_GPUS:-0}" = 1 ]\n' >"$MOCK_DIR/nvidia-smi"
chmod +x "$MOCK_DIR/vulkaninfo" "$MOCK_DIR/nvidia-smi"

# assert_gpu <label> <want> <card-spec>...
# Each card-spec is name:vendor, e.g. card0:0x1002 (sysfs fallback fixtures)
assert_gpu() {
  local label="$1" want="$2" drm got spec name vendor
  shift 2
  drm=$(mktemp -d -p "$MOCK_DIR")
  for spec in "$@"; do
    IFS=: read -r name vendor <<<"$spec"
    mkdir -p "$drm/$name/device"
    echo "$vendor" >"$drm/$name/device/vendor"
  done
  got=$(PATH="$MOCK_DIR:$PATH" STL_DRM_ROOT="$drm" XDG_SESSION_TYPE=x11 \
    bash "$SCRIPT" | jq -r '.gpu_vendor')

  if [[ "$got" == "$want" ]]; then
    printf "  \033[32m✓\033[0m %s\n" "$label"
    ((PASS++)) || true
  else
    printf "  \033[31m✗\033[0m %s\n" "$label"
    printf "      want: %s  got: %s\n" "$want" "$got"
    ((FAIL++)) || true
  fi
}

echo "── detect_gpu_vendor: Vulkan device type ──"
VULKAN_DEVICES="INTEGRATED_GPU:0x1002 DISCRETE_GPU:0x10de" \
  assert_gpu "AMD iGPU listed first, discrete NVIDIA wins" nvidia
VULKAN_DEVICES="INTEGRATED_GPU:0x8086 DISCRETE_GPU:0x1002" \
  assert_gpu "Intel iGPU listed first, discrete AMD wins" amd
VULKAN_DEVICES="INTEGRATED_GPU:0x1002 DISCRETE_GPU:0x8086" \
  assert_gpu "AMD iGPU listed first, discrete Intel Arc wins" intel
VULKAN_DEVICES="CPU:0x10005 INTEGRATED_GPU:0x1002" \
  assert_gpu "llvmpipe ignored, integrated GPU used when no discrete" amd
VULKAN_DEVICES="DISCRETE_GPU:0x10de" \
  assert_gpu "Vulkan result overrides sysfs ranking" nvidia card0:0x1002

echo "── detect_gpu_vendor: fallbacks without Vulkan ──"
assert_gpu "sysfs: AMD card0, NVIDIA card1" nvidia card0:0x1002 card1:0x10de
assert_gpu "sysfs: Intel card0, AMD card1" amd card0:0x8086 card1:0x1002
assert_gpu "sysfs: connector entries are ignored" nvidia \
  card0:0x10de card0-DP-1:0x8086
VULKAN_DEVICES="CPU:0x10005" \
  assert_gpu "only a software renderer in Vulkan falls back to sysfs" intel card0:0x8086
assert_gpu "no Vulkan, no DRM cards" unknown
NVIDIA_SMI_GPUS=1 assert_gpu "no Vulkan, no DRM cards, nvidia-smi lists a GPU" nvidia

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
exit $((FAIL > 0 ? 1 : 0))
