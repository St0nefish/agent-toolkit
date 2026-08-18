#!/usr/bin/env bash
# stl-info.sh - situational report and config linter for SteamTinkerLaunch.
#
#   stl-info.sh                  system report + every game STL knows about
#   stl-info.sh <name|appid>     + full report for one game (fuzzy name match)
#   stl-info.sh -a               lint every game, issues only
#   stl-info.sh -s               system report only
#   stl-info.sh -n <name>        skip the ProtonDB lookup (offline)
#   stl-info.sh -j <name>        emit JSON instead of text
#
# Everything is read live from the system, so nothing goes stale the way a
# written-down version does. Text output is rendered from the same JSON that
# -j emits, so the two can never disagree.
#
# Overridable via environment:
#   STL_CONFIG_DIR   STL config root   (default: $XDG_CONFIG_HOME/steamtinkerlaunch)
#   STEAM_ROOT       Steam install     (default: autodetected, incl. flatpak)
#
# The only network call is ProtonDB's public report summary, cached for a week.

set -uo pipefail

command -v jq >/dev/null || {
  echo "stl-info: jq is required (it builds and renders the report)" >&2
  exit 2
}

# ------------------------------------------------------------- discovery ----
# Steam moves around: native, distro-packaged, and flatpak all differ, and
# ~/.steam/steam is usually a symlink into one of them.
detect_steam_root() {
  local c
  for c in "${STEAM_ROOT:-}" "$HOME/.steam/steam" "$HOME/.steam/root" \
    "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
    "$HOME/Library/Application Support/Steam"; do
    [[ -n "$c" && -d "$c/steamapps" ]] && {
      readlink -f "$c"
      return 0
    }
  done
  return 1
}

STLDIR="${STL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/steamtinkerlaunch}"
STEAMROOT="$(detect_steam_root || true)"
CTOOLS="${STEAMROOT:-$HOME/.steam/steam}/compatibilitytools.d"
STLLOG="/dev/shm/steamtinkerlaunch/steamtinkerlaunch.log"
PDBCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/stl-info/protondb"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_R=$'\e[31m'
  C_Y=$'\e[33m'
  C_G=$'\e[32m'
  C_B=$'\e[1m'
  C_D=$'\e[2m'
  C_0=$'\e[0m'
else
  C_R=""
  C_Y=""
  C_G=""
  C_B=""
  C_D=""
  C_0=""
fi

# ------------------------------------------------------------- utilities ----
# cfgval <file> <key> -> value with surrounding quotes stripped.
# "none" is STL's unset sentinel and is returned verbatim; callers that care
# must treat it as empty.
cfgval() {
  [[ -r "$1" ]] || return 0
  sed -nE "s/^[[:space:]]*$2=[\"']?(.*[^\"'])[\"']?[[:space:]]*\$/\1/p" "$1" | tail -1
}

# lines -> JSON array of strings
json_lines() { jq -R -s 'split("\n") | map(select(length > 0))'; }

human() {
  local b="${1:-}"
  [[ "$b" =~ ^[0-9]+$ ]] || {
    printf '?\n'
    return
  }
  numfmt --to=iec --suffix=B "$b" 2>/dev/null || printf '%s\n' "$b"
}

# pkgver <pkg> -> installed version, whichever package manager is present
pkgver() {
  if command -v pacman >/dev/null; then
    pacman -Q "$1" 2>/dev/null | awk '{print $2}'
  elif command -v dpkg-query >/dev/null; then
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null
  elif command -v rpm >/dev/null; then
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1" 2>/dev/null
  fi
}

steam_libs() {
  [[ -n "$STEAMROOT" ]] || return 0
  printf '%s\n' "$STEAMROOT"
  local vdf="$STEAMROOT/steamapps/libraryfolders.vdf"
  [[ -r "$vdf" ]] && sed -nE 's/.*"path"[[:space:]]+"(.*)".*/\1/p' "$vdf"
}

# --------------------------------------------------------------- indexes ----
# A USEPROTON value can name a custom tool in compatibilitytools.d OR a Steam
# builtin, which lives in <library>/steamapps/common/Proton*/ under a directory
# name that does not match; its internal name is the 2nd field of ./version.
declare -A PROTON_LOC
build_proton_index() {
  local d lib v
  for d in "$CTOOLS"/*; do
    [[ -d "$d" ]] && PROTON_LOC["${d##*/}"]="compatibilitytools.d"
  done
  while read -r lib; do
    [[ -d "$lib/steamapps/common" ]] || continue
    for d in "$lib"/steamapps/common/Proton*; do
      [[ -r "$d/version" ]] || continue
      v="$(awk '{print $2}' "$d/version")"
      [[ -n "$v" ]] && PROTON_LOC["$v"]="Steam builtin (${d##*/})"
    done
  done < <(steam_libs | sort -u)
}

# Installed apps, from every library's appmanifest_*.acf. This is what lets the
# script answer for a game that has no STL config yet.
declare -A APP_NAME APP_PATH APP_SIZE APP_PLAYED APP_PFX APP_PFXPROTON
build_steam_index() {
  local lib m id name dir size played sa
  while read -r lib; do
    sa="$lib/steamapps"
    [[ -d "$sa" ]] || continue
    for m in "$sa"/appmanifest_*.acf; do
      [[ -r "$m" ]] || continue
      id="$(sed -nE 's/.*"appid"[[:space:]]+"([0-9]+)".*/\1/p' "$m" | head -1)"
      [[ -n "$id" ]] || continue
      name="$(sed -nE 's/.*"name"[[:space:]]+"(.*)".*/\1/p' "$m" | head -1)"
      dir="$(sed -nE 's/.*"installdir"[[:space:]]+"(.*)".*/\1/p' "$m" | head -1)"
      size="$(sed -nE 's/.*"SizeOnDisk"[[:space:]]+"([0-9]+)".*/\1/p' "$m" | head -1)"
      played="$(sed -nE 's/.*"LastPlayed"[[:space:]]+"([0-9]+)".*/\1/p' "$m" | head -1)"
      APP_NAME["$id"]="$name"
      APP_PATH["$id"]="$sa/common/$dir"
      APP_SIZE["$id"]="${size:-0}"
      APP_PLAYED["$id"]="${played:-0}"
      if [[ -d "$sa/compatdata/$id" ]]; then
        APP_PFX["$id"]="$sa/compatdata/$id"
        # the prefix records which Proton built it - a mismatch against
        # USEPROTON means the next launch migrates the prefix
        APP_PFXPROTON["$id"]="$(head -1 "$sa/compatdata/$id/version" 2>/dev/null)"
      fi
    done
  done < <(steam_libs | sort -u)
}

declare -A ID2NAME
build_index() {
  local l tgt id f
  for l in "$STLDIR"/gamecfgs/title/*.conf; do
    [[ -e "$l" ]] || continue
    tgt="$(readlink -f "$l")" || continue
    id="$(basename "$tgt" .conf)"
    ID2NAME["$id"]="$(basename "$l" .conf)"
  done
  for f in "$STLDIR"/gamecfgs/id/*.conf; do
    [[ -e "$f" ]] || continue
    id="$(basename "$f" .conf)"
    [[ -n "${ID2NAME[$id]:-}" ]] && continue
    ID2NAME["$id"]="$(cfgval "$STLDIR/meta/id/general/$id.conf" GAMENAME)"
    [[ -z "${ID2NAME[$id]}" ]] && ID2NAME["$id"]="<unnamed>"
  done
}

gname() { printf '%s\n' "${ID2NAME[$1]:-${APP_NAME[$1]:-?}}"; }

# resolve <query> -> appid on stdout; lists candidates and returns 1 if ambiguous
resolve() {
  local q="$1" id pick ql sname aname
  local -a hits=()
  if [[ "$q" =~ ^[0-9]+$ ]] && [[ -f "$STLDIR/gamecfgs/id/$q.conf" || -n "${APP_NAME[$q]:-}" ]]; then
    printf '%s\n' "$q"
    return 0
  fi
  # search STL-configured games and Steam-installed games alike, so a title
  # that has never been run through STL still resolves
  ql="${q,,}"
  for id in $(printf '%s\n' "${!ID2NAME[@]}" "${!APP_NAME[@]}" | sort -un); do
    sname="${ID2NAME[$id]:-}"
    aname="${APP_NAME[$id]:-}"
    if [[ "${sname,,}" == *"$ql"* || "${aname,,}" == *"$ql"* || "$id" == *"$q"* ]]; then
      hits+=("$id")
    fi
  done
  case ${#hits[@]} in
    0)
      printf '%sno game matches%s "%s"\n' "$C_R" "$C_0" "$q" >&2
      return 1
      ;;
    1)
      printf '%s\n' "${hits[0]}"
      return 0
      ;;
  esac
  if command -v fzf >/dev/null && [[ -t 0 && -t 2 && "$JSON" == 0 ]]; then
    pick="$(for id in "${hits[@]}"; do
      printf '%s\t%s%s\n' "$id" "$(gname "$id")" \
        "$([[ -z "${ID2NAME[$id]:-}" ]] && echo '  (no STL config)')"
    done | sort -k2 | fzf --height=40% --prompt='game> ' --with-nth=2.. --delimiter='\t')"
    if [[ -n "$pick" ]]; then
      cut -f1 <<<"$pick"
      return 0
    fi
    return 1
  fi
  printf '%s%d matches for "%s":%s\n' "$C_Y" "${#hits[@]}" "$q" "$C_0" >&2
  for id in "${hits[@]}"; do
    printf '  %-12s %-44s %s\n' "$id" "$(gname "$id")" \
      "$([[ -z "${ID2NAME[$id]:-}" ]] && echo '(no STL config)')" >&2
  done
  return 1
}

# ------------------------------------------------------------ collectors ----
# Hybrid systems are the norm (dGPU + iGPU), and card0 is often the integrated
# one - so scan every card and rank, rather than taking the first hit.
gpu_vendor_ids() {
  local v
  for v in /sys/class/drm/card[0-9]*/device/vendor; do
    [[ -r "$v" ]] && cat "$v"
  done | sort -u
}

detect_gpu_vendor() {
  local ids
  # nvidia-smi responding is definitive: the proprietary stack is loaded
  if command -v nvidia-smi >/dev/null && nvidia-smi -L &>/dev/null; then
    echo nvidia
    return
  fi
  ids="$(gpu_vendor_ids)"
  # rank discrete-capable vendors above Intel, which is nearly always the iGPU
  case "$ids" in
    *0x10de*)
      echo nvidia
      return
      ;;
    *0x1002*)
      echo amd
      return
      ;;
    *0x8086*)
      echo intel
      return
      ;;
  esac
  echo unknown
}

collect_gpu() {
  local vendor loaded model driver_pkg driver_ver base v pkg mesa
  local -a mism=()
  vendor="$(detect_gpu_vendor)"
  loaded=""
  model=""
  driver_pkg=""
  driver_ver=""
  mesa=""

  case "$vendor" in
    nvidia)
      loaded="$(cat /sys/module/nvidia/version 2>/dev/null)"
      # userspace libraries must match the kernel module exactly; distros split
      # them across several packages and a partial upgrade mixes them
      for pkg in nvidia-open-dkms nvidia-dkms nvidia; do
        driver_ver="$(pkgver "$pkg")"
        [[ -n "$driver_ver" ]] && {
          driver_pkg="$pkg"
          break
        }
      done
      if [[ -n "$driver_ver" ]]; then
        base="${driver_ver%%-*}"
        for pkg in nvidia-utils lib32-nvidia-utils nvidia-settings opencl-nvidia \
          lib32-opencl-nvidia nvidia-driver-libs; do
          v="$(pkgver "$pkg")"
          [[ -n "$v" && "${v%%-*}" != "$base" ]] && mism+=("$pkg=$v")
        done
      fi
      command -v nvidia-smi >/dev/null &&
        model="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
      ;;
    amd | intel)
      loaded="$(lsmod 2>/dev/null | awk '$1=="amdgpu"||$1=="i915"||$1=="xe"{print $1; exit}')"
      command -v glxinfo >/dev/null &&
        mesa="$(glxinfo -B 2>/dev/null | sed -nE 's/.*Mesa ([0-9][^ ]*).*/\1/p' | head -1)"
      [[ -z "$mesa" ]] && mesa="$(pkgver mesa)"
      command -v glxinfo >/dev/null &&
        model="$(glxinfo -B 2>/dev/null | sed -nE 's/^\s*Device: (.*)/\1/p' | head -1)"
      ;;
  esac

  jq -n \
    --arg vendor "$vendor" --arg loaded "$loaded" --arg model "$model" \
    --arg pkg "$driver_pkg" --arg ver "$driver_ver" --arg mesa "$mesa" \
    --argjson mismatched "$(printf '%s\n' "${mism[@]+"${mism[@]}"}" | json_lines)" '
    {
      vendor: $vendor,
      model: (if $model == "" then null else $model end),
      loaded_module: (if $loaded == "" then null else $loaded end),
      driver_package: (if $pkg == "" then null else {name: $pkg, version: $ver} end),
      mesa: (if $mesa == "" then null else $mesa end),
      mismatched_packages: $mismatched,
      consistent: ($mismatched | length) == 0
    }'
}

collect_xid() {
  local xid=""
  if [[ "$(detect_gpu_vendor)" == nvidia ]] && command -v journalctl >/dev/null; then
    xid="$(journalctl -k -g Xid --since '14 days ago' --no-pager -o short-iso 2>/dev/null | grep Xid)"
  fi
  jq -n --argjson events "$(printf '%s' "$xid" | json_lines)" \
    '{count: ($events | length), recent: ($events | .[-3:])}'
}

collect_toolchain() {
  local gs mh stl stlbin
  gs=""
  command -v gamescope >/dev/null && {
    gs="$(pkgver gamescope)"
    [[ -z "$gs" ]] && gs="$(gamescope --version 2>&1 |
      sed -nE 's/.*gamescope version ([^ ]+).*/\1/p' | head -1)"
    gs="${gs:-installed}"
  }
  mh=""
  command -v mangohud >/dev/null && mh="$(pkgver mangohud)" && mh="${mh:-installed}"
  stlbin="$(command -v steamtinkerlaunch)"
  stl=""
  # STL's own PROGVERS decides the config format it reads and rewrites; a
  # distro -git package version says nothing useful about that
  [[ -n "$stlbin" ]] && stl="$(sed -nE '1,40s/^PROGVERS="([^"]+)".*/\1/p' "$stlbin" | head -1)"
  jq -n --arg gs "$gs" --arg mh "$mh" --arg stl "$stl" --arg stlbin "$stlbin" \
    --arg st "${XDG_SESSION_TYPE:-}" --arg de "${XDG_CURRENT_DESKTOP:-}" '
    {
      gamescope:         (if $gs  == "" then null else $gs  end),
      mangohud:          (if $mh  == "" then null else $mh  end),
      steamtinkerlaunch: (if $stl == "" then null else $stl end),
      steamtinkerlaunch_path: (if $stlbin == "" then null else $stlbin end),
      session: {type: $st, desktop: $de}
    }'
}

collect_proton() {
  local fam all newest families="{}" missing p ref
  families="$(
    if [[ -d "$CTOOLS" ]]; then
      while read -r fam; do
        [[ "$fam" == "SteamTinkerLaunch" ]] && continue
        all="$(ls -1 "$CTOOLS" | grep -E "^${fam}[-0-9]" | sort -V)"
        [[ -z "$all" ]] && continue
        newest="$(tail -1 <<<"$all")"
        jq -n --arg fam "$fam" --arg newest "$newest" \
          --argjson installed "$(printf '%s' "$all" | json_lines)" \
          '{key: $fam, value: {newest: $newest, installed: $installed}}'
      done < <(ls -1 "$CTOOLS" | sed -E 's/[0-9].*$//; s/-+$//' | sort -u | grep .)
    fi | jq -s 'from_entries'
  )"
  # protons referenced by a game config that resolve to nothing on disk
  missing=""
  ref="$(grep -h '^USEPROTON=' "$STLDIR"/gamecfgs/id/*.conf 2>/dev/null |
    cut -d= -f2- | tr -d '"' | sort -u | grep .)"
  while read -r p; do
    [[ -z "$p" || "$p" == "none" || -n "${PROTON_LOC[$p]:-}" ]] && continue
    missing+="$p"$'\n'
  done <<<"$ref"
  jq -n --argjson families "${families:-\{\}}" \
    --argjson missing "$(printf '%s' "$missing" | json_lines)" \
    '{compatibilitytools_d: $families, referenced_but_missing: $missing}'
}

collect_system() {
  local gpu xid tool proton libs
  gpu="$(collect_gpu)"
  xid="$(collect_xid)"
  tool="$(collect_toolchain)"
  proton="$(collect_proton)"
  libs="$(steam_libs | sort -u | json_lines)"
  jq -n --argjson gpu "$gpu" --argjson xid "$xid" --argjson tool "$tool" \
    --argjson proton "$proton" --argjson libs "$libs" \
    --arg stldir "$STLDIR" --arg steamroot "$STEAMROOT" --arg ctools "$CTOOLS" '
    {
      gpu: $gpu,
      xid: $xid,
      toolchain: $tool,
      paths: {
        stl_config_dir: $stldir,
        stl_config_dir_exists: ($stldir | test("^/")),
        steam_root: (if $steamroot == "" then null else $steamroot end),
        compatibilitytools_d: $ctools,
        steam_libraries: $libs
      },
      proton: $proton
    }'
}

# system-level findings, in the same shape as the per-game lint
collect_system_lint() {
  local sys="$1"
  jq -n --argjson s "$sys" --arg stldir "$STLDIR" '
    [
      (if ($s.gpu.consistent | not)
       then {level:"error", message:("driver package set is MIXED: " +
              ($s.gpu.mismatched_packages | join(", ")))} else empty end),
      (if ($s.gpu.loaded_module != null and $s.gpu.driver_package != null and
            ($s.gpu.driver_package.version | split("-")[0]) != $s.gpu.loaded_module)
       then {level:"error", message:("installed " +
              ($s.gpu.driver_package.version | split("-")[0]) + " != running " +
              $s.gpu.loaded_module + " - REBOOT NEEDED")} else empty end),
      (if $s.xid.count > 0
       then {level:"warn", message:("\($s.xid.count) Xid event(s) in 14d - a GPU fault, not a config bug")}
       else empty end),
      (if $s.paths.steam_root == null
       then {level:"error", message:"no Steam install found - set STEAM_ROOT"} else empty end),
      (if $s.toolchain.steamtinkerlaunch == null
       then {level:"warn", message:"steamtinkerlaunch not found in PATH"} else empty end),
      ($s.proton.referenced_but_missing[] |
        {level:"error", message:("referenced by a game config but not installed anywhere: " + .)})
    ]'
}

# -------------------------------------------------------------- protondb ----
# Only one ProtonDB endpoint is public: the per-appid report summary. The
# per-report endpoints all 404, so tier/score/confidence is all we can get.
# Cached for a week; a stale cache beats nothing when offline.
protondb() {
  local id="$1"
  local c="$PDBCACHE/$id.json"
  ((NONET)) && return 1
  command -v curl >/dev/null || return 1
  if [[ -f "$c" ]] && [[ -n "$(find "$c" -mtime -7 2>/dev/null)" ]]; then
    cat "$c"
    return 0
  fi
  mkdir -p "$PDBCACHE"
  if curl -sf --max-time 8 -o "$c.tmp" \
    "https://www.protondb.com/api/v1/reports/summaries/${id}.json" && [[ -s "$c.tmp" ]]; then
    mv "$c.tmp" "$c"
    cat "$c"
    return 0
  fi
  rm -f "$c.tmp"
  [[ -f "$c" ]] && {
    cat "$c"
    return 0
  }
  return 1
}

collect_protondb() {
  local id="$1" j
  if j="$(protondb "$id")" && jq -e . >/dev/null 2>&1 <<<"$j"; then
    jq --arg url "https://www.protondb.com/app/$id" '. + {page: $url}' <<<"$j"
  else
    echo null
  fi
}

# ------------------------------------------------------------------ lint ----
# Each check encodes a rule the skill documents, so the rules are enforced
# rather than remembered. Emits "level<TAB>message" lines.
lint_lines() {
  local id="$1"
  local cfg="$STLDIR/gamecfgs/id/$id.conf" cv="$STLDIR/gamecfgs/customvars/$id.conf"
  local proton gs gsargs mangoapp mangohud vkd3d rt gameargs v W H gw gh lo extra
  local E=$'error\t' W_=$'warn\t'

  [[ -f "$cfg" ]] || return 0

  proton="$(cfgval "$cfg" USEPROTON)"
  if [[ -n "$proton" && "$proton" != "none" && -z "${PROTON_LOC[$proton]:-}" ]]; then
    echo "${E}USEPROTON=\"$proton\" resolves to nothing on disk"
  fi

  gs="$(cfgval "$cfg" USEGAMESCOPE)"
  gsargs="$(cfgval "$cfg" GAMESCOPE_ARGS)"
  mangoapp="$(cfgval "$cfg" USEMANGOAPP)"
  mangohud="$(cfgval "$cfg" USEMANGOHUD)"

  if [[ "$mangoapp" == "1" ]]; then
    echo "${E}USEMANGOAPP=1 - STL wedges on waitForGamePid under gamescope (upstream #1153). Use 0 + --mangoapp in GAMESCOPE_ARGS."
  fi

  if [[ "$gs" == "1" ]]; then
    [[ "$gsargs" == *-- ]] || echo "${E}GAMESCOPE_ARGS must end with '--'"
    [[ "$mangohud" == "1" ]] && echo "${W_}USEMANGOHUD=1 under gamescope - use gamescope's own --mangoapp instead"
    if [[ "$gsargs" != *--mangoapp* && "$mangohud" != "1" ]]; then
      echo "${W_}no overlay (no --mangoapp in GAMESCOPE_ARGS)"
    fi
    if [[ "$gsargs" == *--hdr-enabled* && "$(cfgval "$cv" ENABLE_GAMESCOPE_WSI)" != "1" ]]; then
      echo "${E}--hdr-enabled but customvars lacks ENABLE_GAMESCOPE_WSI=1 - HDR will not light up"
    fi
    W="$(grep -oE '(^| )-W +[0-9]+' <<<"$gsargs" | grep -oE '[0-9]+' | tail -1)"
    H="$(grep -oE '(^| )-H +[0-9]+' <<<"$gsargs" | grep -oE '[0-9]+' | tail -1)"
    gameargs="$(cfgval "$cfg" GAMEARGS)"
    gw="$(grep -oE '\-screen-width +[0-9]+' <<<"$gameargs" | grep -oE '[0-9]+')"
    gh="$(grep -oE '\-screen-height +[0-9]+' <<<"$gameargs" | grep -oE '[0-9]+')"
    [[ -n "$gw" && -n "$W" && "$gw" != "$W" ]] &&
      echo "${W_}GAMEARGS -screen-width $gw != gamescope -W $W (renders as a box)"
    [[ -n "$gh" && -n "$H" && "$gh" != "$H" ]] &&
      echo "${W_}GAMEARGS -screen-height $gh != gamescope -H $H"
  elif [[ "$gsargs" == *--hdr-enabled* ]]; then
    echo "${W_}GAMESCOPE_ARGS carries --hdr-enabled but USEGAMESCOPE=0"
  fi

  # legacy winewayland / vk-hdr-layer HDR route
  for v in PROTON_ENABLE_WAYLAND PROTON_ENABLE_HDR ENABLE_HDR_WSI; do
    [[ "$(cfgval "$cv" "$v")" == "1" ]] &&
      echo "${E}customvars sets $v - legacy HDR route, conflicts with gamescope WSI"
  done

  vkd3d="$(cfgval "$cfg" STL_VKD3D_CONFIG)"
  rt="$(cfgval "$cfg" USERAYTRACING)"
  if [[ "$vkd3d" == *descriptor_heap* && "$proton" != proton-cachyos* ]]; then
    echo "${W_}STL_VKD3D_CONFIG has descriptor_heap but USEPROTON is \"$proton\" (needs Proton-CachyOS)"
  fi
  # USERAYTRACING=1 makes STL hard-set VKD3D_CONFIG=dxr11, discarding whatever
  # STL_VKD3D_CONFIG held. Only a problem when that field carries something a
  # bare dxr11 would not cover - a lone "dxr"/"dxr11" loses nothing.
  if [[ "$rt" == "1" && -n "$vkd3d" && "$vkd3d" != "none" ]]; then
    extra="$(tr ',' '\n' <<<"$vkd3d" | grep -vxE 'dxr|dxr11|' | paste -sd,)"
    [[ -n "$extra" ]] &&
      echo "${E}USERAYTRACING=1 makes STL overwrite VKD3D_CONFIG=dxr11, discarding \"$extra\". Set USERAYTRACING=0 and add -dx12 to GAMEARGS."
  fi
  if [[ -n "$(cfgval "$cv" VKD3D_CONFIG)" && -n "$vkd3d" && "$vkd3d" != "none" ]]; then
    echo "${W_}VKD3D_CONFIG in customvars AND STL_VKD3D_CONFIG set - double definition"
  fi

  # Steam launch options must stay empty under STL - STL is itself the wrapper
  if [[ -n "$STEAMROOT" ]]; then
    lo="$(grep -A6 "^[[:space:]]*\"$id\"\$" "$STEAMROOT/userdata/"*/config/localconfig.vdf 2>/dev/null |
      grep -m1 '"LaunchOptions"' | sed -E 's/.*"LaunchOptions"[[:space:]]+"(.*)".*/\1/')"
    [[ -n "$lo" ]] &&
      echo "${E}Steam LaunchOptions not empty (\"$lo\") - STL is the wrapper, keep it empty"
  fi

  return 0
}

collect_lint() {
  lint_lines "$1" | jq -R -s '
    split("\n") | map(select(length > 0)) |
    map(split("\t") | {level: .[0], message: .[1]})'
}

# ------------------------------------------------------------ game object ---
collect_game() {
  local id="$1"
  local cfg="$STLDIR/gamecfgs/id/$id.conf" cv="$STLDIR/gamecfgs/customvars/$id.conf"
  local meta="$STLDIR/meta/id/general/$id.conf"
  local l link="" pl gl steam stl k fields="{}" cvlines proton fam newest

  for l in "$STLDIR"/gamecfgs/title/*.conf; do
    [[ -e "$l" && "$(readlink -f "$l")" == "$cfg" ]] && {
      link="$l"
      break
    }
  done

  if [[ -n "${APP_NAME[$id]:-}" ]]; then
    steam="$(jq -n \
      --arg name "${APP_NAME[$id]}" --arg path "${APP_PATH[$id]}" \
      --argjson size "${APP_SIZE[$id]:-0}" --argjson played "${APP_PLAYED[$id]:-0}" \
      --arg human "$(human "${APP_SIZE[$id]:-0}")" \
      --arg pfx "${APP_PFX[$id]:-}" --arg pfxproton "${APP_PFXPROTON[$id]:-}" \
      --argjson exists "$([[ -d "${APP_PATH[$id]}" ]] && echo true || echo false)" '
      {
        name: $name, install_path: $path, install_path_exists: $exists,
        size_on_disk: $size, size_human: $human,
        last_played: (if $played == 0 then null else $played end),
        prefix: (if $pfx == "" then null else $pfx + "/pfx" end),
        prefix_built_by: (if $pfxproton == "" then null else $pfxproton end)
      }')"
  else
    steam=null
  fi

  if [[ -f "$cfg" ]]; then
    for k in USEPROTON USEGAMEMODERUN USESLR USEREAP GAMEARGS HARDARGS \
      USEGAMESCOPE GAMESCOPE_ARGS USEMANGOAPP USEMANGOHUD \
      DXVK_HDR DXVK_ASYNC USEDLSS USERAYTRACING PROTON_ENABLE_NVAPI \
      PROTON_HIDE_NVIDIA_GPU STL_VKD3D_CONFIG STL_VKD3D_FILTER_DEVICE_NAME; do
      fields="$(jq --arg k "$k" --arg v "$(cfgval "$cfg" "$k")" \
        '. + {($k): (if $v == "" then null else $v end)}' <<<"$fields")"
    done
    cvlines="$(grep -vE '^[[:space:]]*(#|$)' "$cv" 2>/dev/null | json_lines)"
    proton="$(cfgval "$cfg" USEPROTON)"
    fam="$(sed -E 's/[0-9].*$//; s/-+$//' <<<"$proton")"
    newest="$(ls -1 "$CTOOLS" 2>/dev/null | grep -E "^${fam}[-0-9]" | sort -V | tail -1)"
    pl="$STLDIR/logs/proton/id/steam-$id.log"
    gl="$STLDIR/logs/gamelaunch/id/$id.log"
    stl="$(jq -n \
      --argjson fields "$fields" --argjson customvars "$cvlines" \
      --arg cfg "$cfg" --arg cv "$([[ -f "$cv" ]] && echo "$cv")" \
      --arg meta "$([[ -f "$meta" ]] && echo "$meta")" --arg link "$link" \
      --arg loc "${PROTON_LOC[$proton]:-}" --arg newest "$newest" \
      --arg pl "$pl" --arg gl "$gl" \
      --arg plsize "$([[ -f "$pl" ]] && du -h "$pl" | cut -f1)" \
      --arg pldate "$([[ -f "$pl" ]] && date -r "$pl" '+%Y-%m-%d %H:%M')" \
      --arg glsize "$([[ -f "$gl" ]] && du -h "$gl" | cut -f1)" \
      --arg gldate "$([[ -f "$gl" ]] && date -r "$gl" '+%Y-%m-%d %H:%M')" \
      --argjson clean "$(grep -q 'Primary child shut down' "$gl" 2>/dev/null && echo true || echo false)" '
      {
        configured: true,
        paths: {
          id_config: $cfg,
          customvars: (if $cv == "" then null else $cv end),
          meta: (if $meta == "" then null else $meta end),
          title_symlink: (if $link == "" then null else $link end)
        },
        proton: {
          name: $fields.USEPROTON,
          location: (if $loc == "" then null else $loc end),
          installed: ($loc != ""),
          newest_in_family: (if $newest == "" then null else $newest end)
        },
        fields: $fields,
        customvars: $customvars,
        logs: {
          proton: (if $plsize == "" then null else {path:$pl, size:$plsize, modified:$pldate} end),
          gamelaunch: (if $glsize == "" then null else {path:$gl, size:$glsize, modified:$gldate, clean_exit:$clean} end)
        }
      }')"
  else
    stl='{"configured": false}'
  fi

  jq -n --arg id "$id" --arg name "$(gname "$id")" \
    --argjson steam "$steam" --argjson stl "$stl" \
    --argjson protondb "$(collect_protondb "$id")" \
    --argjson lint "$(collect_lint "$id")" \
    --arg pfxproton "${APP_PFXPROTON[$id]:-}" '
    {
      appid: $id, name: $name, steam: $steam, protondb: $protondb, stl: $stl,
      prefix_migration_pending: (
        $pfxproton != "" and $stl.configured and $stl.proton.name != null and
        $pfxproton != $stl.proton.name
      ),
      lint: $lint
    }'
}

# ------------------------------------------------------------- renderers ----
hdr() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
kv() { printf '  %-28s %s\n' "$1" "${2:-}"; }

render_lint() {
  local arr="$1" level msg
  if [[ "$(jq 'length' <<<"$arr")" == 0 ]]; then
    printf '  %s[ ok ]%s no issues found\n' "$C_G" "$C_0"
    return
  fi
  while IFS=$'\t' read -r level msg; do
    case "$level" in
      error) printf '  %s[ERR ]%s %s\n' "$C_R" "$C_0" "$msg" ;;
      warn) printf '  %s[WARN]%s %s\n' "$C_Y" "$C_0" "$msg" ;;
      *) printf '  [%s] %s\n' "$level" "$msg" ;;
    esac
  done < <(jq -r '.[] | [.level, .message] | @tsv' <<<"$arr")
}

render_system() {
  local s="$1" lint="$2" v
  hdr "GPU / driver"
  kv "vendor" "$(jq -r '.gpu.vendor' <<<"$s")"
  v="$(jq -r '.gpu.model // empty' <<<"$s")" && [[ -n "$v" ]] && kv "GPU" "$v"
  v="$(jq -r '.gpu.loaded_module // empty' <<<"$s")" && [[ -n "$v" ]] && kv "loaded module" "$v"
  v="$(jq -r '.gpu.driver_package | if . == null then empty else "\(.name) \(.version)" end' <<<"$s")"
  [[ -n "$v" ]] && kv "driver package" "$v"
  v="$(jq -r '.gpu.mesa // empty' <<<"$s")" && [[ -n "$v" ]] && kv "mesa" "$v"
  if [[ "$(jq -r '.gpu.consistent' <<<"$s")" == true ]]; then
    printf '  %s[ ok ]%s driver package set consistent\n' "$C_G" "$C_0"
  fi

  hdr "Recent Xid (kernel journal, 14d)"
  if [[ "$(jq -r '.xid.count' <<<"$s")" == 0 ]]; then
    printf '  %s[ ok ]%s no Xid events\n' "$C_G" "$C_0"
  else
    kv "events" "$(jq -r '.xid.count' <<<"$s")"
    jq -r '.xid.recent[]' <<<"$s" | cut -c1-140 | sed 's/^/    /'
  fi

  hdr "Toolchain"
  for v in gamescope mangohud steamtinkerlaunch; do
    kv "$v" "$(jq -r --arg k "$v" '.toolchain[$k] // "not installed"' <<<"$s")"
  done
  kv "session" "$(jq -r '"\(.toolchain.session.type) / \(.toolchain.session.desktop)"' <<<"$s")"

  hdr "Paths"
  kv "STL config dir" "$(jq -r '.paths.stl_config_dir' <<<"$s")"
  kv "Steam root" "$(jq -r '.paths.steam_root // "not found"' <<<"$s")"
  kv "Steam libraries" "$(jq -r '.paths.steam_libraries | length' <<<"$s")"

  hdr "Proton tools (newest per family)"
  if [[ "$(jq -r '.proton.compatibilitytools_d | length' <<<"$s")" == 0 ]]; then
    kv "status" "none installed"
  else
    while IFS=$'\t' read -r fam newest cnt; do
      printf '  %s%-16s%s newest: %-44s (%s installed)\n' "$C_B" "$fam" "$C_0" "$newest" "$cnt"
    done < <(jq -r '.proton.compatibilitytools_d | to_entries[] |
      [.key, .value.newest, (.value.installed | length)] | @tsv' <<<"$s")
  fi

  [[ "$(jq 'length' <<<"$lint")" != 0 ]] && {
    hdr "System findings"
    render_lint "$lint"
  }
  return 0
}

render_game() {
  local g="$1" v
  hdr "$(jq -r '"\(.name)  (\(.appid))"' <<<"$g")"

  if [[ "$(jq -r '.steam' <<<"$g")" == null ]]; then
    kv "steam install" "not installed in any Steam library"
  else
    kv "steam name" "$(jq -r '.steam.name' <<<"$g")"
    kv "install path" "$(jq -r '.steam.install_path + (if .steam.install_path_exists then "" else "  [dir missing]" end)' <<<"$g")"
    kv "size on disk" "$(jq -r '.steam.size_human' <<<"$g")"
    v="$(jq -r '.steam.last_played // empty' <<<"$g")"
    if [[ -n "$v" ]]; then
      kv "last played" "$(date -d "@$v" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$v")"
    else
      kv "last played" "never"
    fi
    kv "wine prefix" "$(jq -r '.steam.prefix // "none yet (created on first Proton launch)"' <<<"$g")"
    v="$(jq -r '.steam.prefix_built_by // empty' <<<"$g")"
    [[ -n "$v" ]] && kv "prefix built by" "$v"
  fi

  hdr "ProtonDB"
  if [[ "$(jq -r '.protondb' <<<"$g")" == null ]]; then
    kv "status" "no data (offline, no reports, or --no-net)"
  else
    kv "tier" "$(jq -r '.protondb.tier // "?"' <<<"$g")"
    kv "trending" "$(jq -r '.protondb.trendingTier // "?"' <<<"$g")"
    kv "best reported" "$(jq -r '.protondb.bestReportedTier // "?"' <<<"$g")"
    kv "score / confidence" "$(jq -r '"\(.protondb.score // "?") / \(.protondb.confidence // "?")  (\(.protondb.total // 0) reports)"' <<<"$g")"
    kv "page" "$(jq -r '.protondb.page' <<<"$g")"
  fi

  if [[ "$(jq -r '.stl.configured' <<<"$g")" != true ]]; then
    hdr "STL config"
    printf '  %s[WARN]%s no STL config for this appid - not set up in STL yet\n' "$C_Y" "$C_0"
    printf '  %s\n' \
      "Launch it once with SteamTinkerLaunch as its compatibility tool, or copy" \
      "an existing gamecfgs/id/<appid>.conf and edit it."
    return
  fi

  kv "id config" "$(jq -r '.stl.paths.id_config' <<<"$g")"
  kv "customvars" "$(jq -r '.stl.paths.customvars // "none"' <<<"$g")"
  kv "meta" "$(jq -r '.stl.paths.meta // "none"' <<<"$g")"
  kv "title symlink" "$(jq -r '.stl.paths.title_symlink // "none"' <<<"$g")"

  hdr "Runtime"
  kv "USEPROTON" "$(jq -r '"\(.stl.proton.name)  [\(.stl.proton.location // "MISSING")]"' <<<"$g")"
  v="$(jq -r 'if .stl.proton.newest_in_family != null and .stl.proton.newest_in_family != .stl.proton.name then .stl.proton.newest_in_family else empty end' <<<"$g")"
  [[ -n "$v" ]] && kv "newest in family" "$v"
  # a prefix built by a different Proton gets migrated on next launch - that is
  # the one-time slow first launch, not a fault
  [[ "$(jq -r '.prefix_migration_pending' <<<"$g")" == true ]] &&
    kv "prefix mismatch" "prefix built by $(jq -r '.steam.prefix_built_by' <<<"$g") - next launch migrates it"
  for v in USEGAMEMODERUN USESLR USEREAP GAMEARGS HARDARGS; do
    kv "$v" "$(jq -r --arg k "$v" '.stl.fields[$k] // ""' <<<"$g")"
  done

  hdr "gamescope / overlay"
  for v in USEGAMESCOPE GAMESCOPE_ARGS USEMANGOAPP USEMANGOHUD; do
    kv "$v" "$(jq -r --arg k "$v" '.stl.fields[$k] // ""' <<<"$g")"
  done

  hdr "Graphics / HDR"
  for v in DXVK_HDR DXVK_ASYNC USEDLSS USERAYTRACING PROTON_ENABLE_NVAPI \
    PROTON_HIDE_NVIDIA_GPU STL_VKD3D_CONFIG STL_VKD3D_FILTER_DEVICE_NAME; do
    kv "$v" "$(jq -r --arg k "$v" '.stl.fields[$k] // ""' <<<"$g")"
  done

  [[ "$(jq '.stl.customvars | length' <<<"$g")" != 0 ]] && {
    hdr "customvars (effective lines)"
    jq -r '.stl.customvars[]' <<<"$g" | sed 's/^/  /'
  }

  hdr "Logs"
  jq -r '.stl.logs | to_entries[] |
    if .value == null then "  \(.key): absent"
    else "  \(.key): \(.value.path)  \(.value.size)  \(.value.modified)" end' <<<"$g"
  [[ "$(jq -r '.stl.logs.gamelaunch.clean_exit // false' <<<"$g")" == true ]] &&
    kv "gamelaunch" "has 'Primary child shut down!' (game itself exited cleanly)"
  if [[ -f "$STLLOG" ]] && grep -q 'waitForGamePid' "$STLLOG" 2>/dev/null; then
    printf '  %s[WARN]%s %s waitForGamePid lines in the live STL log - the #1153 wedge\n' \
      "$C_Y" "$C_0" "$(grep -c 'waitForGamePid' "$STLLOG")"
  fi

  hdr "Lint"
  render_lint "$(jq '.lint' <<<"$g")"
  return 0
}

# ------------------------------------------------------------------ main ----
usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
  exit 0
}

MODE="one"
QUERY=""
NONET=0
JSON=0
while (($#)); do
  case "$1" in
    -a | --all) MODE="all" ;;
    -s | --system) MODE="system" ;;
    -n | --no-net) NONET=1 ;;
    -j | --json) JSON=1 ;;
    -h | --help) usage ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *) QUERY="$1" ;;
  esac
  shift
done

if [[ ! -d "$STLDIR" ]]; then
  printf '%sSTL config dir not found:%s %s\n' "$C_R" "$C_0" "$STLDIR" >&2
  printf 'Set STL_CONFIG_DIR if SteamTinkerLaunch keeps its config elsewhere.\n' >&2
  exit 2
fi

build_index
build_proton_index
build_steam_index
IDS="$(printf '%s\n' "${!ID2NAME[@]}" | sort -n)"

SYS="$(collect_system)"
SYSLINT="$(collect_system_lint "$SYS")"
OUT="$(jq -n --argjson system "$SYS" --argjson lint "$SYSLINT" \
  '{system: ($system + {lint: $lint})}')"

case "$MODE" in
  system) ;;
  all)
    GAMES="$(for id in $IDS; do
      jq -n --arg id "$id" --arg name "$(gname "$id")" \
        --argjson lint "$(collect_lint "$id")" \
        '{appid: $id, name: $name, lint: $lint}'
    done | jq -s '.')"
    OUT="$(jq --argjson games "$GAMES" '. + {games: $games}' <<<"$OUT")"
    ;;
  one)
    if [[ -n "$QUERY" ]]; then
      id="$(resolve "$QUERY")" || exit 1
      OUT="$(jq --argjson game "$(collect_game "$id")" '. + {game: $game}' <<<"$OUT")"
    else
      GAMES="$(for id in $IDS; do
        cfg="$STLDIR/gamecfgs/id/$id.conf"
        jq -n --arg id "$id" --arg name "${ID2NAME[$id]}" \
          --arg proton "$(cfgval "$cfg" USEPROTON)" \
          --argjson gs "$([[ "$(cfgval "$cfg" USEGAMESCOPE)" == 1 ]] && echo true || echo false)" \
          '{appid: $id, name: $name, proton: $proton, gamescope: $gs}'
      done | jq -s '.')"
      UNCONF="$(for id in "${!APP_NAME[@]}"; do
        [[ -n "${ID2NAME[$id]:-}" ]] && continue
        [[ "${APP_NAME[$id]}" == Proton* || "${APP_NAME[$id]}" == Steam* ]] && continue
        jq -n --arg id "$id" --arg name "${APP_NAME[$id]}" \
          --arg size "$(human "${APP_SIZE[$id]:-0}")" \
          '{appid: $id, name: $name, size_human: $size}'
      done | jq -s 'sort_by(.name)')"
      OUT="$(jq --argjson games "$GAMES" --argjson unconf "$UNCONF" \
        '. + {games: $games, unconfigured: $unconf}' <<<"$OUT")"
    fi
    ;;
esac

NERR="$(jq '[.. | objects | select(has("level")) | select(.level == "error")] | length' <<<"$OUT")"
NWARN="$(jq '[.. | objects | select(has("level")) | select(.level == "warn")] | length' <<<"$OUT")"

if ((JSON)); then
  jq --argjson e "$NERR" --argjson w "$NWARN" \
    '. + {summary: {errors: $e, warnings: $w}}' <<<"$OUT"
else
  render_system "$(jq '.system' <<<"$OUT")" "$SYSLINT"
  case "$MODE" in
    all)
      hdr "Config lint ($(jq '.games | length' <<<"$OUT") games)"
      if [[ "$(jq '[.games[] | select(.lint | length > 0)] | length' <<<"$OUT")" == 0 ]]; then
        printf '  %s[ ok ]%s all clean\n' "$C_G" "$C_0"
      else
        while read -r id; do
          printf '\n%s%-10s %s%s\n' "$C_B" "$id" "$(gname "$id")" "$C_0"
          render_lint "$(jq --arg i "$id" '.games[] | select(.appid == $i) | .lint' <<<"$OUT")"
        done < <(jq -r '.games[] | select(.lint | length > 0) | .appid' <<<"$OUT")
      fi
      ;;
    one)
      if [[ -n "$QUERY" ]]; then
        render_game "$(jq '.game' <<<"$OUT")"
      else
        hdr "Games configured in STL ($(jq '.games | length' <<<"$OUT"))"
        jq -r '.games[] | "  \(.appid)\t\(.name)\t\(.proton)\t\(if .gamescope then "gamescope" else "" end)"' <<<"$OUT" |
          awk -F'\t' '{printf "  %-11s %-40s %-30s %s\n", $1, $2, $3, $4}'
        if [[ "$(jq '.unconfigured | length' <<<"$OUT")" != 0 ]]; then
          hdr "Installed, no STL config ($(jq '.unconfigured | length' <<<"$OUT"))"
          jq -r '.unconfigured[] | [.appid, .name, .size_human] | @tsv' <<<"$OUT" |
            awk -F'\t' '{printf "  %-11s %-40s %s\n", $1, $2, $3}'
        fi
      fi
      ;;
  esac
  printf '\n%s---%s %s error(s), %s warning(s)\n' "$C_D" "$C_0" "$NERR" "$NWARN"
fi

[[ "$NERR" -gt 0 ]] && exit 1
exit 0
