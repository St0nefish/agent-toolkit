#!/usr/bin/env bash
# test-system-info.sh — assertions for check_kde_hdr_enabled and
# detect_gpu_vendor in system-info.sh.
# HDR: a PATH-injected kscreen-doctor mock prints fixture JSON for -j, so the
# result depends only on the fixture: HDR state of the primary (priority 1)
# enabled output, false on anything unparseable or non-KDE.
# GPU: STL_DRM_ROOT points at a fixture tree of cardN/device/vendor files.

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

# Empty vulkaninfo and GPU-less nvidia-smi mocks so the no-card fallbacks are
# hermetic; NVIDIA_SMI_GPUS=1 makes nvidia-smi report a GPU
printf '#!/usr/bin/env bash\n' >"$MOCK_DIR/vulkaninfo"
printf '#!/usr/bin/env bash\n[ "${NVIDIA_SMI_GPUS:-0}" = 1 ]\n' >"$MOCK_DIR/nvidia-smi"
chmod +x "$MOCK_DIR/vulkaninfo" "$MOCK_DIR/nvidia-smi"

# assert_gpu <label> <want> <card-spec>...
# Each card-spec is name:vendor[:vram_bytes], e.g. card0:0x1002:536870912
assert_gpu() {
  local label="$1" want="$2" drm got spec name vendor vram
  shift 2
  drm=$(mktemp -d -p "$MOCK_DIR")
  for spec in "$@"; do
    IFS=: read -r name vendor vram <<<"$spec"
    mkdir -p "$drm/$name/device"
    echo "$vendor" >"$drm/$name/device/vendor"
    [ -n "$vram" ] && echo "$vram" >"$drm/$name/device/mem_info_vram_total"
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

echo "── detect_gpu_vendor ──"
assert_gpu "AMD iGPU as card0, NVIDIA dGPU as card1" nvidia \
  card0:0x1002:536870912 card1:0x10de
assert_gpu "Intel iGPU as card0, discrete AMD as card1" amd \
  card0:0x8086 card1:0x1002:17163091968
assert_gpu "AMD iGPU as card0, Intel Arc as card1" intel \
  card0:0x1002:536870912 card1:0x8086
assert_gpu "AMD iGPU only" amd card0:0x1002:536870912
assert_gpu "connector entries are ignored" nvidia \
  card0:0x10de card0-DP-1:0x8086
assert_gpu "no DRM cards, no vulkan match" unknown
NVIDIA_SMI_GPUS=1 assert_gpu "no DRM cards, nvidia-smi lists a GPU" nvidia

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
exit $((FAIL > 0 ? 1 : 0))
