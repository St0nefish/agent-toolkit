# STL Game Config

Configure Steam games via SteamTinkerLaunch with automated system detection and template-based configuration.

## Overview

This skill automatically configures Steam games for Linux gaming using SteamTinkerLaunch (STL). It detects your system capabilities (GPU, compositor, HDR, API support) and applies the appropriate Proton/DXVK/VKD3D settings through template selection.

## Features

- **System Detection**: Automatically identifies GPU vendor (NVIDIA/AMD/Intel), compositor (KDE/Wayland), HDR capability, and graphics API support
- **Template Selection**: Applies the right configuration templates based on system detection and game requirements
- **Per-Game Configs**: Creates per-game STL configs with proper DX12/RT, DLSS, and HDR settings
- **Retro Gaming Support**: CPU affinity and compatibility settings for pre-2010 games

## Usage

Invoke via: `/stl-game-config` or let the skill trigger automatically when you ask about Steam game configuration.

## What It Does

1. **Gets game info** - Game name, any specific issues
2. **Detects system** - Runs `system-info.sh` to gather GPU, compositor, HDR, API data
3. **Researches game** - dispatches a read-only research subagent against ProtonDB and PCGamingWiki for AppID, API, RT/DLSS/HDR support; the agent reports only the key findings back, keeping raw page content out of the main session
4. **Selects templates** - Chooses base + GPU + compositor + API templates based on detection
5. **Creates config** - Writes per-game STL configuration files (gamecfgs/id/{APPID}.conf)
6. **Verifies** - Confirms config exists and provides testing/MangoHud verification guidance

## System Requirements

- SteamTinkerLaunch installed and configured
- Linux with KDE Plasma (Wayland) - the plugin assumes this environment (SteamOS uses this)
- Steam games library

## Template Structure

```text
templates/
├── base.conf              # Always-safe defaults (GameMode, MangoHud, DXVK async)
├── gpu-nvidia.conf        # NVIDIA-specific (NVAPI, GPU detection)
├── gpu-amd.conf           # AMD-specific settings
├── compositor-kde.conf    # KDE HDR integration
├── api-dx12-rt.conf       # DX12 + Ray Tracing (VKD3D_CONFIG=dxr)
├── api-dx12-nort.conf     # DX12 without RT
├── api-dx11.conf          # DX11/Vulkan (DXVK)
└── api-dx9.conf           # Retro DirectX 9 settings
```

## Template Selection Logic

The `select-template.sh` script determines which templates to apply:

```text
if GPU is NVIDIA → include gpu-nvidia.conf
if GPU is AMD → include gpu-amd.conf
if compositor is KDE → include compositor-kde.conf
if API is DX12 + RT → include api-dx12-rt.conf
if API is DX12 only → include api-dx12-nort.conf
if API is DX11 → include api-dx11.conf
if API is DX9 → include api-dx9.conf
```

Templates are concatenated in priority order to produce the final per-game configuration.

## HDR Configuration

HDR is only configured if:

1. System detection shows KDE HDR is enabled on primary monitor
2. Game supports HDR (detected via PCGamingWiki/ProtonDB)

For KDE, we check HDR state programmatically - no user input needed unless HDR isn't detected but the game supports it.

## Retro Gaming

Pre-2010 games (DX9) get special handling:

- CPU affinity via `taskset -c 0-3` (or appropriate core range)
- `WINE_CPU_TOPOLOGY` set for legacy Wine
- `PULSE_LATENCY_MSEC` for audio stability
- `DXVK_FRAME_RATE` cap to fix timing issues

## See Also

- [SteamTinkerLaunch Wiki](https://github.com/sonic2kk/steamtinkerlaunch/wiki)
- [ProtonDB](https://www.protondb.com/) - Game compatibility database
- [PCGamingWiki](https://www.pcgamingwiki.com/) - Game-specific technical details
