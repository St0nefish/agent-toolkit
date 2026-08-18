# STL Game Config

Inspect, lint, and configure Steam games via SteamTinkerLaunch (STL).

## Overview

Two halves. The **inspector** reports live system and per-game state and lints
configs against known-bad patterns. The **generator** builds a new per-game
config from templates after detecting GPU vendor, compositor, HDR capability,
and the game's graphics API.

Nothing about the host is hardcoded — every fact is read at runtime, so the
plugin does not go stale as drivers, Proton builds, and library paths change.

## Usage

Invoke the skill with `/stl-game-config`, or run the scripts directly.

### Inspector

```bash
scripts/stl-info.sh                  # system report + every game STL knows about
scripts/stl-info.sh "<name|appid>"   # + full report for one game (fuzzy match)
scripts/stl-info.sh -a               # lint every game, issues only
scripts/stl-info.sh -s               # system report only
scripts/stl-info.sh -j "<name>"      # JSON instead of text
scripts/stl-info.sh -n "<name>"      # skip the ProtonDB lookup (offline)
```

Reports the GPU vendor and driver (including whether the loaded kernel module
matches the installed packages), recent GPU faults, gamescope/MangoHud/STL
versions, the newest Proton per family, and for a given game its config paths,
resolved Proton, gamescope and HDR fields, customvars, wine prefix, and log
freshness — plus its ProtonDB tier.

Game lookup covers **titles with no STL config yet**: it indexes every Steam
library's `appmanifest_*.acf`, so an unconfigured game still resolves by name
and reports its install path, size, and prefix. Exit status is non-zero when any
error-level finding is present.

### JSON output

`-j` emits the whole report as JSON so a caller can select one field instead of
parsing text. Text output is rendered from this same JSON, so the two cannot
disagree.

```bash
scripts/stl-info.sh -j -s | jq -r '.system.gpu.vendor'
scripts/stl-info.sh -j "cyberpunk" | jq -r '.game.stl.fields.GAMESCOPE_ARGS'
scripts/stl-info.sh -j -a | jq -r '.games[] | select(.lint|length>0)
                                    | "\(.name): \(.lint[].message)"'
scripts/stl-info.sh -j -a | jq '.summary'      # {errors, warnings}
```

Top-level keys: `system` (with `.lint`), `game` **or** `games` +
`unconfigured`, and `summary`.

### What it lints

| Finding | Why it matters |
|---|---|
| `USEMANGOAPP=1` | STL wedges on `waitForGamePid` under gamescope ([#1153](https://github.com/sonic2kk/steamtinkerlaunch/issues/1153)) |
| `GAMESCOPE_ARGS` not ending in `--` | STL appends the game command after it |
| `--hdr-enabled` without `ENABLE_GAMESCOPE_WSI=1` | HDR silently does nothing |
| legacy HDR vars set | conflicts with gamescope's WSI layer |
| `USERAYTRACING=1` clobbering `STL_VKD3D_CONFIG` | STL overwrites the field |
| `USEPROTON` resolving to nothing | renamed or deleted Proton build |
| non-empty Steam launch options | STL is already the wrapper |
| game resolution ≠ gamescope `-W`/`-H` | game renders as a small box |
| mixed driver packages / module ≠ installed | partial upgrade, needs reboot |

### Generator

```bash
bash scripts/system-info.sh                       # GPU / compositor / HDR as JSON
SYSTEM_INFO=$(bash scripts/system-info.sh)
bash scripts/generate-stl-config.sh "$SYSTEM_INFO" "$API" "$HDR" "$APPID" "$NAME"
```

## Configuration

| Variable | Default |
|---|---|
| `STL_CONFIG_DIR` | `$XDG_CONFIG_HOME/steamtinkerlaunch` |
| `STEAM_ROOT` | autodetected — native, distro-packaged, or flatpak |

## Requirements

- SteamTinkerLaunch installed
- `jq` — the inspector builds and renders its report with it
- `curl` for the ProtonDB lookup — optional, `-n` skips it
- `fzf` for interactive disambiguation — optional, falls back to a printed list

gamescope and HDR guidance assumes a Wayland compositor with HDR support, but
the inspector and generator work on any Linux desktop; the GPU and compositor
are detected, not assumed.

## Templates

```text
templates/
├── base.conf         # safe defaults applied to every game
├── gpu.conf          # per-vendor device filtering and shader cache
├── api.conf          # per-graphics-API settings (DX12+RT, DX12, DX11, DX9)
├── hdr.conf          # both HDR routes, and the legacy vars to avoid
└── customvars.conf   # env vars with no native STL field
```

Each is a commented block set — uncomment the section matching the detected GPU,
graphics API, and HDR state, then concatenate.

## HDR

The route depends on the translation layer the game uses, not its era:

| Game API | Layer | How HDR is enabled |
|---|---|---|
| D3D9/10/11 | DXVK | `DXVK_HDR=1` |
| D3D12 | VKD3D | `ENABLE_GAMESCOPE_WSI=1` + `--hdr-enabled` in `GAMESCOPE_ARGS` |

Both parts of the DX12 route are required. The legacy winewayland /
vk-hdr-layer route (`PROTON_ENABLE_WAYLAND`, `PROTON_ENABLE_HDR`,
`ENABLE_HDR_WSI`) conflicts with gamescope's own WSI layer and is flagged as an
error by the linter.

## gamescope

gamescope is a nested compositor — it runs the game inside its own XWayland, so
no host-side tool or window rule can see the game's window. The practical
consequences (never set `USEMANGOAPP`, always terminate `GAMESCOPE_ARGS` with
`--`, match the game's internal resolution to `-W`/`-H`) are documented in the
skill and enforced by the linter.

## Retro titles

Pre-2010 DX9 games get CPU affinity via `taskset`, `WINE_CPU_TOPOLOGY`, a pulse
latency bump for audio stability, and a `DXVK_FRAME_RATE` cap for engines whose
timing breaks at high frame rates.

## See Also

- [SteamTinkerLaunch wiki](https://github.com/sonic2kk/steamtinkerlaunch/wiki)
- [gamescope](https://github.com/ValveSoftware/gamescope)
- [ProtonDB](https://www.protondb.com/)
- [PCGamingWiki](https://www.pcgamingwiki.com/)
