---
name: stl-game-config
description: Configure Steam games via SteamTinkerLaunch with automated system detection and template-based configuration. Detects GPU vendor (NVIDIA/AMD/Intel), compositor (KDE/Wayland), HDR capability, and graphics API to generate optimal Proton/DXVK/VKD3D settings. Handles modern DX12/RT games and retro DX9 titles.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch
---

# STL Game Config Skill

Configure Steam games for optimal performance on Linux using SteamTinkerLaunch with automated system detection.

## System Hardware

- **CPU**: AMD Ryzen 7 7800X3D (8C/16T)
- **GPU**: NVIDIA GeForce RTX 5090 (32GB VRAM)
- **Display**: 2560x1440 @ 240Hz OLED with HDR (KDE Wayland)

## Configuration File Locations

| File | Purpose |
|------|---------|
| `~/.config/steamtinkerlaunch/global.conf` | Global settings |
| `~/.config/steamtinkerlaunch/default_template.conf` | Template for new games |
| `~/.config/steamtinkerlaunch/gamecfgs/id/{APPID}.conf` | Per-game config |
| `~/.config/steamtinkerlaunch/gamecfgs/customvars/{APPID}.conf` | Per-game environment vars |

## Workflow

**Tools by step:**

- **System Detection**: Bash (system-info.sh script)
- **Game Research**: WebFetch (ProtonDB, PCGamingWiki), Grep/Glob (knowledge base)
- **Template Generation**: Bash (generate-stl-config.sh script)
- **Verification**: Bash (file checks), Read (logs)

### Step 1: Get Game Info

Ask for **game name**. Note any specific issues (won't launch, crashes, poor performance).

### Step 2: Detect System

Run the system-info.sh script to gather system capabilities:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/system-info.sh
```

Parse the JSON output to determine:
- GPU vendor (nvidia/amd/intel)
- Compositor (kde/gnome/other)
- KDE HDR enabled status

### Step 3: Research Game

Gather all required data before configuration:

**Data points to collect:**

| Data | Primary Source | Fallback |
|------|----------------|----------|
| Steam App ID | Steam store URL, SteamDB | WebSearch |
| Graphics API | PCGamingWiki "API" section | ProtonDB comments |
| RT/DLSS/HDR | PCGamingWiki "Features" | In-game settings |
| Linux issues | ProtonDB reports | - |
| Existing config | `/gaming/games/` | Create new |

**Web research workflow:**

1. **Find App ID**: Extract from Steam store URL or search SteamDB
2. **ProtonDB** (`https://www.protondb.com/app/{APPID}`):
   - Rating (Platinum/Gold/Silver/Bronze/Borked)
   - Top 3 reported issues from recent reviews
   - Recommended Proton version if mentioned
3. **PCGamingWiki** (`https://www.pcgamingwiki.com/wiki/{Game_Name}`):
   - Exact graphics API (look for "API" row in specs table)
   - Ray tracing support and type
   - Known Linux/Proton issues
4. **Knowledge base**: `Glob: /gaming/games/*{game-name}*.md`

**Anti-cheat note:** If ProtonDB mentions EAC/BattlEye issues, check [areweanticheatyet.com](https://areweanticheatyet.com/) - some games require developer opt-in for Linux support.

### Step 4: Present Findings

```text
## {Game Name} - Feature Analysis

**Steam App ID**: {APPID}
**Graphics API**: {API}

| Feature | Supported | Notes |
|---------|-----------|-------|
| Ray Tracing | Yes/No | {type} |
| DLSS | Yes/No | |
| HDR | Yes/No | |

**ProtonDB Rating**: {rating}
**Known Issues**: {summary}
```

Ask: "I'll enable all supported features. Any you want to skip?"

### Step 5: Generate Config

Generate per-game config using the template system:

```bash
SYSTEM_INFO=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/system-info.sh)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-stl-config.sh "$SYSTEM_INFO" "$GAME_API" "$GAME_HDR" "$APPID" "$GAME_NAME"
```

This outputs a complete config with:
- Base safe defaults (GameMode, MangoHud, etc.)
- GPU-specific settings (NVIDIA/AMD/Intel)
- API-specific settings (DX12-RT, DX12, DX11, DX9)
- HDR settings (only if KDE HDR detected AND game supports it)

### Step 6: Write Configuration

Write to `~/.config/steamtinkerlaunch/gamecfgs/id/{APPID}.conf`

### Step 7: Verify Configuration

1. **Confirm config exists:**

   ```bash
   ls ~/.config/steamtinkerlaunch/gamecfgs/id/{APPID}.conf
   ```

2. **Test launch** - Watch for STL loading message in terminal

3. **MangoHud verification** (once in-game):
   - `API: VKD3D` = DX12 mode active (VKD3D-Proton translating)
   - `API: VK` = DX11/Vulkan mode (DXVK translating)
   - GPU name visible = NVAPI working

4. **If issues**: See troubleshooting in `/gaming/tools/steamtinkerlaunch.md`

### Step 8: Provide Summary

After configuration:

1. **Summary** - What was configured and why
2. **Expected behavior** - What the user should see
3. **Fallback options** - Reference relevant troubleshooting docs if issues occur

---

## Templates Reference

### Base Template (`base.conf`)
Always safe defaults for all games:
```bash
PROTON_ENABLE_NVAPI="1"
PROTON_HIDE_NVIDIA_GPU="0"
DXVK_ASYNC="1"
USEGAMEMODERUN="1"
USEMANGOHUD="1"
```

### GPU Template (`gpu.conf`)
Uncomment section based on your GPU vendor:

| GPU | Settings |
|-----|----------|
| NVIDIA | `PROTON_ENABLE_NVAPI`, `NVAPI`, `GPU filtering`, `VKD3D shader cache` |
| AMD | `GPU filtering`, `VKD3D shader cache` |
| Intel | `GPU filtering` |

### API Template (`api.conf`)
Uncomment section based on game's graphics API:

| Game Type | Settings |
|-----------|----------|
| DX12 + RT | `STL_VKD3D_CONFIG="dxr"`, `USERAYTRACING="1"`, `USEDLSS="1"` |
| DX12 (no RT) | `STL_VKD3D_CONFIG="none"`, `USERAYTRACING="0"`, `USEDLSS="1"` |
| DX11 | `STL_VKD3D_CONFIG="none"`, `USERAYTRACING="0"`, `DXVK_HDR="1"` |
| DX9 | `taskset`, `WINE_CPU_TOPOLOGY`, `DXVK_FRAME_RATE` |

**Critical notes:**
- `VKD3D_CONFIG="dxr"` is **required** for DX12 RT detection
- `USERAYTRACING=1` on DX11/Vulkan causes launch failures

### HDR Template (`hdr.conf`)
Uncomment when KDE HDR is enabled AND game supports HDR:

| Game Type | Settings |
|-----------|----------|
| DX12 | `PROTON_ENABLE_HDR="1"`, `ENABLE_HDR_WSI="1"` |
| DX11 | `PROTON_ENABLE_HDR="1"`, `ENABLE_HDR_WSI="1"`, `DXVK_HDR="1"` |

**Prerequisites:**
1. Install vk-hdr-layer: `paru -S vk-hdr-layer-kwin6-git`
2. Enable KDE HDR: System Settings → Display → Enable HDR
3. Calibrate peak brightness to match monitor spec

### Custom Variables Template (`customvars.conf`)
For env vars not in STL: GPU filtering, VKD3D shader cache, retro settings

---

## External Resources

- [SteamTinkerLaunch Wiki](https://github.com/sonic2kk/steamtinkerlaunch/wiki)
- [VKD3D-Proton Environment Variables](https://github.com/HansKristian-Work/vkd3d-proton#environment-variables)
- [DXVK Configuration](https://github.com/doitsujin/dxvk#configuration)
- [ProtonDB](https://www.protondb.com/)