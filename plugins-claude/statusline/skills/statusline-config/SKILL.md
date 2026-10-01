---
disable-model-invocation: true
name: statusline-config
description: "View or edit status line configuration"
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# Status Line Config

View or modify the claude-statusline configuration file.

Config location: `${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/config.json`

## Available settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `rows` | array of arrays | `[["user","dir","git"],["model","context","usage"],["extra","cost"]]` | One inner array per status line row, each an ordered list of segments. Rows with nothing to show are skipped. |
| `segments` | array | — | Legacy single-row form; only used when `rows` is absent. |
| `dir_style` | string | `"project"` | `"project"` shows only the project name; `"path"` shows the abbreviated path (see `path_max_length`) |
| `align` | boolean | `true` | Pad segments so separators line up vertically across rows |
| `usage_extra` | boolean | `false` | Fold extra credits into the `usage` segment instead of a separate `extra` segment |
| `context_style` | string | `"bar"` | `"bar"` (stretches to fill its column, 8-24 cells), `"icon"` (`◔ 11%`) or `"text"` (`Ctx 11%`) |
| `context_bar_min` | number | `8` | Smallest context bar, in cells |
| `context_bar_max` | number | `24` | Largest a stretched context bar grows to; a value below the min is raised to it |
| `context_bar_default` | number | `10` | Bar size when it has no column to fill (last cell on a row, or `align: false`) |
| `session_icon` | string | `"◷"` | Icon for the 5-hour window in `usage`; `""` falls back to `5h` |
| `week_icon` | string | `"▦"` | Icon for the 7-day window in `usage`; `""` falls back to `7d` |
| `dir_icon` | string | `"⌂"` | Icon before the project name; `""` disables |
| `git_icon` | string | `"⎇"` | Icon before the branch name; `""` disables |
| `worktree_marker` | string | `"⧉"` | Appended to the project name inside a linked git worktree; `""` disables |
| `git_branch_max_length` | number | `40` | Ellipsize the middle of long branch names; `0` disables |
| `separator` | string | `" \| "` | String displayed between segments |
| `cache_ttl` | number | `300` | API usage cache TTL in seconds |
| `git_cache_ttl` | number | `5` | Git status cache TTL in seconds |
| `path_max_length` | number | `40` | Max characters for directory display (only with `dir_style: "path"`) |
| `show_host` | string | `"auto"` | Show hostname: `"auto"` (SSH only), `"always"`, `"never"` |
| `git_backend` | string | `"auto"` | Git backend: `"auto"`, `"daemon"` (gitstatusd only), `"cli"` (git only) |
| `label_style` | string | `"short"` | Label format: `"short"` (Ctx, Ses, Wk) or `"long"` (Context, Session, Week) |
| `cost_thresholds` | array | `[5, 20]` | Dollar values for green/yellow/red cost coloring |
| `extra_hide_zero` | boolean | `true` | Hide extra credits segment when $0 used |
| `extra_only_burning` | boolean | `false` | Only show extra segment when session or weekly is at 100% |
| `currency` | string | `"$"` | Currency symbol prefix |
| `colors` | object | *(see below)* | 256-color codes or keywords (`dim`, `bold`, `default`) for each element |

### Color keys

`low`, `mid`, `high`, `separator`, `git_branch_feature`, `git_branch_primary`, `git_staged`, `git_unstaged`, `git_untracked`, `git_ahead`, `git_behind`, `label`, `model`, `user`, `user_root`, `host`, `dir`, `reset_time`, `cost`

## Instructions

1. Read the config file at `${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/config.json`. If it does not exist, tell the user to run `/statusline:statusline-setup` first.

2. Show the user the current configuration.

3. Ask what they want to change using `AskUserQuestion`.

4. Edit the config file with the requested changes using `Edit`.

5. Let the user know the changes take effect automatically on the next status line refresh (no restart needed).
