---
name: stl-game-config
description: >-
  Inspect, lint, fix, and create SteamTinkerLaunch (STL) game configs on Linux.
  Use when a Steam game won't launch, crashes, stutters, renders at the wrong
  resolution or as a small box, has no HDR, picks the wrong GPU, or when Steam
  keeps showing it as "Running" after it exited. Also use when choosing a Proton
  or GE-Proton build, setting up gamescope or MangoHud, enabling ray tracing or
  DLSS, tuning VKD3D/DXVK, checking what ProtonDB says about a title, or
  auditing existing STL configs. Triggers on SteamTinkerLaunch, STL config,
  Proton, gamescope, VKD3D, DXVK, ProtonDB, and Linux gaming setup questions.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent
---

# STL Game Config Skill

Inspect, lint, and configure Steam games for Linux using SteamTinkerLaunch (STL).

## When to use this

Reach for this whenever a Linux gaming question touches Steam, Proton, or STL —
whether the user is debugging one misbehaving title or setting up a new one.

| Symptom | Where to look first |
|---|---|
| Steam shows the game "Running" after it exited | the `USEMANGOAPP` wedge, below |
| Game renders as a small box in the corner | resolution vs gamescope `-W`/`-H` |
| HDR does nothing | the HDR route table — DX11 and DX12 differ |
| Crash or GPU hang on a DX12/RT title | the descriptor-heap playbook |
| Hitching on first-seen effects | shader cache — DX12 and DX11 use different vars |
| Game lands on the iGPU | device filtering |
| Won't launch at all, no STL popup | Steam launch options conflicting with STL |
| Very slow first launch after a change | the first-launch tax — usually not a fault |

For "is this game any good on Linux", the inspector already returns the ProtonDB
tier — start there rather than opening a browser.

**Always run the inspector before answering.** Driver versions, Proton build
names, and install paths drift constantly; a value recalled from an earlier
session or another game's config is the single most common source of a broken
config.

## Start Here: `stl-info.sh`

**Run this before anything else. Never hand-assemble the facts it reports** —
driver versions, Proton build names, and install paths all drift, and a stale
value copied from memory is the most common source of a broken config.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh                  # system + all known games
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh "<name|appid>"   # + one game in full
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -a               # lint every game, issues only
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -s               # system only
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -j "<name>"      # JSON instead of text
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -n "<name>"      # skip the ProtonDB lookup
```

Game lookup is fuzzy on name or appid and covers **titles with no STL config
yet** — it indexes every Steam library's `appmanifest_*.acf`, so an
unconfigured game still resolves and reports its install path, size, and wine
prefix. Exit status is non-zero when any error-level finding is present.

### Prefer `-j` and pull just what you need

Text output is for humans. When you need one fact, take the JSON and select it
— it keeps whole reports out of context:

```bash
S=${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh

"$S" -j -s | jq -r '.system.gpu.vendor'                      # nvidia | amd | intel
"$S" -j -s | jq -r '.system.proton.compatibilitytools_d
                     | to_entries[] | "\(.key): \(.value.newest)"'
"$S" -j "cyberpunk" | jq -r '.game.appid'
"$S" -j "cyberpunk" | jq -r '.game.stl.fields.GAMESCOPE_ARGS'
"$S" -j "cyberpunk" | jq -r '.game.protondb.tier'
"$S" -j -a | jq -r '.games[] | select(.lint|length>0)
                     | "\(.name): \(.lint[].message)"'       # every finding
"$S" -j -a | jq '.summary'                                   # {errors, warnings}
```

Top-level JSON keys: `system` (with `.lint`), `game` **or** `games` +
`unconfigured`, and `summary`. Text output is rendered from this same JSON, so
the two can never disagree.

### What it lints

Each check encodes one rule from this document, so the rules are enforced
rather than remembered. If you change a rule here, change the check too.

| Finding | Why |
|---|---|
| `USEMANGOAPP=1` | the gamescope wedge — see below |
| `GAMESCOPE_ARGS` not ending in `--` | STL appends the command after it |
| `--hdr-enabled` without `ENABLE_GAMESCOPE_WSI=1` | HDR silently does nothing |
| legacy HDR vars set | conflicts with the gamescope WSI layer |
| `USERAYTRACING=1` clobbering `STL_VKD3D_CONFIG` | STL overwrites the field |
| `USEPROTON` resolving to nothing | renamed or deleted Proton build |
| non-empty Steam launch options | STL is already the wrapper |
| game resolution ≠ gamescope `-W`/`-H` | game renders as a small box |
| driver package set mixed / module ≠ installed | partial upgrade, needs reboot |

## Environment

Nothing about the host is hardcoded — **detect it, don't assume it**:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/system-info.sh     # GPU vendor, compositor, HDR
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -j -s       # full live system report
```

`stl-info.sh` honours two overrides when the defaults are wrong:

| Variable | Default |
|---|---|
| `STL_CONFIG_DIR` | `$XDG_CONFIG_HOME/steamtinkerlaunch` |
| `STEAM_ROOT` | autodetected: native, distro, or flatpak |

### Config file locations

| File | Purpose |
|------|---------|
| `<stl-config>/global.conf` | Global settings |
| `<stl-config>/default_template.conf` | Template STL applies to new games |
| `<stl-config>/gamecfgs/id/{APPID}.conf` | Per-game config (every STL field) |
| `<stl-config>/gamecfgs/customvars/{APPID}.conf` | Per-game environment vars |
| `<stl-config>/gamecfgs/title/{Name}.conf` | Symlink → the `id/` config |

Proton builds live in `<steam-root>/compatibilitytools.d/`. **`USEPROTON` must
match a tool's internal name there exactly** — version strings drift constantly,
so read the current name from `stl-info.sh` rather than reusing one from another
game's config.

### On-disk gotchas

Three places where the name on disk is not the name you expect. The inspector
already handles all three; these are here so the output makes sense.

- **A Steam builtin Proton has no matching directory name.** `USEPROTON` can
  name a builtin like `proton-8.0-5d`, which lives at
  `<library>/steamapps/common/Proton 8.0/`. The link between them is the second
  field of that directory's `version` file. Searching `compatibilitytools.d`
  alone will wrongly conclude the Proton is missing.
- **A game's install directory is not its store name.** The manifest's
  `installdir` is authoritative — e.g. *Tom Clancy's Ghost Recon Wildlands*
  installs to `common/Wildlands`. Never construct an install path from the
  title; read it from the `appmanifest_*.acf`.
- **A wine prefix records the Proton that built it**, in
  `<library>/steamapps/compatdata/<appid>/version`. When that differs from
  `USEPROTON`, the next launch migrates the prefix — which is a slow first
  launch, not a fault.

### STL rewrites configs on launch

When STL's own version has moved on, the first launch of a game **rewrites**
that game's `gamecfgs/id/<appid>.conf` into the current format — adding new
fields and a new version header. Expect unrelated churn in the diff after a test
launch, and re-read the file before editing it rather than working from a copy
read earlier in the session.

## gamescope

gamescope is a **nested compositor**: it starts its own XWayland server and runs
the game inside it. Two consequences drive everything below.

**Nothing on the host can see the game's window.** `xwininfo`, `xdotool`,
`xprop`, window-manager rules — all look at the host display, and the game is
not there. The host sees only gamescope's own toplevel, whose Wayland `app_id`
is the literal string `gamescope` for **every** game (its title starts as
`Gamescope` and becomes the game's title only after the window maps). Per-game
window rules therefore cannot target a gamescope'd game — delete them rather
than trying to retarget them.

**Never enable STL's `USEMANGOAPP`.** It selects STL's `runMA` branch, which
backgrounds the game and then calls `waitForGamePid` to re-attach. That resolves
the PID with `xwininfo -name "$GAMEWINDOW"` against the host display — which,
per above, can never succeed under gamescope — and the loop has no timeout. STL
spins forever, so Steam keeps showing the game as "Running" until Stop is
pressed, long after the game and gamescope have both exited cleanly. Upstream:
[steamtinkerlaunch#1153](https://github.com/sonic2kk/steamtinkerlaunch/issues/1153),
open and unfixed. The failure is invisible during play — the game runs fine,
only the exit is broken.

Working setup for a gamescope title:

| Field | Value |
|---|---|
| `USEGAMESCOPE` | `1` |
| `USEMANGOAPP` | `0` — always |
| `USEMANGOHUD` | `0` — gamescope's overlay replaces it |
| `GAMESCOPE_ARGS` | include `--mangoapp` for the overlay; **must end with `--`** |
| `ENABLE_GAMESCOPE_WSI` | `1` in customvars, for HDR |

Let gamescope start the overlay itself via its own `--mangoapp` flag ("You
should use this instead of using mangohud on the game or gamescope"). STL then
takes its normal synchronous gamescope path, which never calls `waitForGamePid`
and exits cleanly. Check `GAMESCOPE_ARGS` before flipping any toggle — some
configs already carry `--mangoapp`, in which case `USEMANGOAPP=1` was starting a
redundant second instance.

**Match the game's internal resolution to gamescope's `-W`/`-H`.** gamescope
does not stretch a smaller surface to fill; a game told to render smaller than
the gamescope surface shows up as a small box centred in it. Engine flags
(`-screen-width` / `-screen-height` for Unity, etc.) go in `GAMEARGS`.

**Diagnosing a game the launcher won't let go of:** check
`/dev/shm/steamtinkerlaunch/steamtinkerlaunch.log` for repeated
`waitForGamePid - Waiting for game process` lines — that is this bug.
gamescope's own output is tee'd to `<stl-config>/logs/gamelaunch/id/<appid>.log`;
`Primary child shut down!` there confirms the game really did exit and only STL
is stuck.

## HDR

The route depends on the translation layer the game actually uses:

| Game API | Layer | How HDR is enabled |
|---|---|---|
| D3D9/10/11 | DXVK | `DXVK_HDR=1` |
| D3D12 | VKD3D | gamescope: `ENABLE_GAMESCOPE_WSI=1` + `--hdr-enabled` in `GAMESCOPE_ARGS` |

Both parts of the DX12 route are required; neither alone does anything. DXVK
only handles D3D9-11, so on a DX12-only title `DXVK_HDR` is inert — harmless to
leave set for consistency, but it is not what lights up HDR.

**Do not use the legacy winewayland / vk-hdr-layer route.**
`PROTON_ENABLE_WAYLAND` puts wine back on `winewayland.drv`; `ENABLE_HDR_WSI`
loads the standalone vk-hdr-layer shim, and stacking that under gamescope's own
WSI layer invites conflicts. `PROTON_ENABLE_HDR` only sets `DXVK_HDR=1`, so it
does nothing for DX12. `stl-info.sh` flags all three as errors.

The standalone vk-hdr-layer package is **not** needed for the gamescope route.
The compositor still needs HDR enabled and peak brightness calibrated to the
panel's spec.

## Known-Issue Playbooks

- **GPU fault / hang on heavy DX12+RT workloads** (NVIDIA logs these as `Xid`
  in the kernel journal; `stl-info.sh` surfaces recent ones). The strong fix is
  the descriptor-heap path: `STL_VKD3D_CONFIG=descriptor_heap`, which needs a
  recent driver **and** a Proton-CachyOS build. For RT titles combine as
  `dxr11,descriptor_heap` and set `USERAYTRACING=0` so STL does not overwrite
  `VKD3D_CONFIG` — then add `-dx12` to `GAMEARGS` manually. Lesser fallbacks:
  `__GL_THREADED_OPTIMIZATIONS=0`, then forcing DX11 via `GAMEARGS="-dx11"`
  (stable, but reintroduces shader stutter). These crashes are **intermittent**
  and also fire at exit, so a short clean test is not proof of a fix.
- **Shader-compilation stutter** (hitches on first-seen effects): prefer the
  DX12/VKD3D path with a warm `VKD3D_SHADER_CACHE` over DX11/DXVK.
  DX12 → `VKD3D_SHADER_CACHE`; DX11 → `DXVK_STATE_CACHE`. Setting the DXVK one
  on a DX12-only title does nothing.
- **First-launch tax**: the first launch after a driver swap or Proton change
  grinds through one-time work — runtime regeneration, shader pre-caching, and
  prefix migration if the Proton changed. `stl-info.sh` reports
  `prefix_migration_pending` when the prefix was built by a different Proton
  than `USEPROTON` names. For anti-cheat titles the first launch can outright
  crash; retry before concluding it is broken.
- **Wrapper args conflict**: never put `gamemoderun` / `mangohud` / `gamescope
  %command%` in a game's **Steam launch options** when it is on STL — STL is
  itself the wrapper and applies them via `USEGAMEMODERUN` / `USEMANGOHUD`. The
  combination is fragile and can stop the game launching with no STL popup at
  all. Keep Steam launch options empty; `stl-info.sh` flags any that are not.
- **Wrong GPU selected** (game lands on the iGPU): set
  `DXVK_FILTER_DEVICE_NAME` / `VKD3D_FILTER_DEVICE_NAME` to the vendor string,
  optionally with `DXVK_VULKAN_DEVICE=0` / `VKD3D_VULKAN_DEVICE=0`.

## Conventions

- **NVAPI split**: modern DX12/DLSS titles use `PROTON_ENABLE_NVAPI=1` +
  `PROTON_HIDE_NVIDIA_GPU=0`; retro titles use the inverse.
- **STL field mapping**: `STL_VKD3D_CONFIG` becomes the `VKD3D_CONFIG` env var.
  Prefer the native STL field over hand-setting the env var in customvars, to
  avoid a double definition.
- **Quote style varies per file** — match the existing style of the file being
  edited (some use `KEY=value`, some `KEY="value"`).
- **Verify env var names against upstream docs.** Forum flags are often myths —
  e.g. `PROTON_NO_NGX_UPDATER` does not exist; the real variable is
  `PROTON_ENABLE_NGX_UPDATER`. Do not cargo-cult.
- **Launching a game and swapping a GPU driver are system-level actions.** Do
  not do either without an explicit instruction for that specific action.

## Workflow: configuring a new game

### Step 1: Identify the game

Ask for the game name and note any specific symptom (won't launch, crashes,
poor performance). Then resolve it — this works before any config exists:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh -j "<name>" | jq '{
  appid: .game.appid, installed: (.game.steam != null),
  configured: .game.stl.configured, protondb: .game.protondb.tier }'
```

### Step 2: Detect the system

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/system-info.sh
```

Parse the JSON for GPU vendor, compositor, and HDR status. Never assume these.

### Step 3: Research the game (delegate — do not fetch inline)

**Do this research in a subagent.** ProtonDB and PCGamingWiki pages are long and
noisy; fetching them inline floods the main context. Dispatch via the `Agent`
tool with `subagent_type: research` (falls back to `general-purpose`), one agent
per game, and have it return **only** the structured findings — never raw page
text.

Note `stl-info.sh` already returns the ProtonDB tier/score/confidence from the
public summary API, so the agent only needs the parts that API does not carry.

**Data points the agent collects:**

| Data | Primary source | Fallback |
|------|----------------|----------|
| Graphics API | PCGamingWiki "API" section | ProtonDB reports |
| RT / DLSS / HDR support | PCGamingWiki "Features" | in-game settings |
| Known Linux issues | ProtonDB reports | — |
| Recommended Proton | ProtonDB reports | — |
| Anti-cheat status | [areweanticheatyet.com](https://areweanticheatyet.com/) | — |

The agent's prompt must include the game name, the appid, the list above, the
source URLs, and an explicit instruction: *"Report only the structured summary.
Do not paste raw page content, comment threads, or review text."*

### Step 4: Present findings

```text
## {Game Name} ({APPID}) - Feature Analysis

**Graphics API**: {API}

| Feature | Supported | Notes |
|---------|-----------|-------|
| Ray Tracing | Yes/No | {type} |
| DLSS | Yes/No | |
| HDR | Yes/No | |

**ProtonDB**: {tier} (trending {trending}, {n} reports)
**Known Issues**: {summary}
```

Ask: "I'll enable all supported features. Any you want to skip?"

### Step 5: Generate the config

```bash
SYSTEM_INFO=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/system-info.sh)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-stl-config.sh \
  "$SYSTEM_INFO" "$GAME_API" "$GAME_HDR" "$APPID" "$GAME_NAME"
```

Write the result to `<stl-config>/gamecfgs/id/{APPID}.conf`.

### Step 6: Verify

Re-run the inspector — it is the check, and it is non-zero on any error:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/stl-info.sh "{APPID}"
```

Then on first launch:

- MangoHud `API: VKD3D` = DX12 active; `API: VK` = DX11/Vulkan via DXVK
- GPU name visible in the overlay = NVAPI working
- The first launch is slow by design (see the first-launch tax above)

### Step 7: Summarize

State what was configured and why, what to expect on first launch, and which
fallback from the playbooks applies if it misbehaves.

## Templates Reference

| Template | Contents |
|---|---|
| `base.conf` | safe defaults applied to every game |
| `gpu.conf` | per-vendor device filtering and shader cache |
| `api.conf` | per-graphics-API settings (DX12+RT, DX12, DX11, DX9) |
| `hdr.conf` | both HDR routes, and the legacy vars to avoid |
| `customvars.conf` | env vars with no native STL field |

**Critical notes:**

- `VKD3D_CONFIG="dxr"` is required for DX12 ray-tracing detection
- `USERAYTRACING=1` on a DX11/Vulkan title causes launch failures
- `USERAYTRACING=1` overwrites `STL_VKD3D_CONFIG` — see the playbook above

## External Resources

- [SteamTinkerLaunch wiki](https://github.com/sonic2kk/steamtinkerlaunch/wiki)
- [VKD3D-Proton environment variables](https://github.com/HansKristian-Work/vkd3d-proton#environment-variables)
- [DXVK configuration](https://github.com/doitsujin/dxvk#configuration)
- [gamescope](https://github.com/ValveSoftware/gamescope)
- [ProtonDB](https://www.protondb.com/)
