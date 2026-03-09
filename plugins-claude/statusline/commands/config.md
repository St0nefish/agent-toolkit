---
description: "View or edit status line configuration"
allowed-tools: Bash, Read, Edit, AskUserQuestion
disable-model-invocation: true
---

# Status Line Config

View or modify the claude-statusline configuration file.

Config location: `${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/config.json`

## Available settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `segments` | array | `["user","dir","git","model","context","session","weekly","extra","cost"]` | Ordered list of segments to display. Remove items to disable them. |
| `separator` | string | `" \| "` | String displayed between segments |
| `cache_ttl` | number | `300` | API usage cache TTL in seconds |
| `git_cache_ttl` | number | `5` | Git status cache TTL in seconds |
| `path_max_length` | number | `40` | Max characters for directory display |
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

1. Read the config file at `${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/config.json`. If it does not exist, tell the user to run `/statusline:setup` first.

2. Show the user the current configuration.

3. Ask what they want to change using `AskUserQuestion`.

4. Edit the config file with the requested changes using `Edit`.

5. Let the user know the changes take effect automatically on the next status line refresh (no restart needed).
