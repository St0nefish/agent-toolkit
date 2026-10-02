# Statusline

Configurable status line for Claude Code showing git status, model, context usage, API utilization, and session cost with ANSI colors.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/statusline
```

That's it. Start a new session and the status line appears from the session
after that. Claude Code plugins can't set `statusLine` themselves, so a
`SessionStart` hook does the setup for you the first time it runs:

- It copies the scripts and a default `config.json` to
  `~/.config/claude-statusline/` and adds `statusLine` to
  `~/.claude/settings.json`.
- It is **add-only**: if your settings already define a `statusLine` (yours or
  another tool's), nothing is written. Your existing `config.json` is never
  overwritten.
- It is silent, and it needs `jq`.

### Updates

The same hook keeps the installed copy current. It compares the installed
scripts with the ones in the plugin version that just loaded and refreshes any
that differ, so after `claude plugin update` the new status line is live from
your next session start. Files are swapped in atomically, so a refresh
mid-update can't run a half-written script. There is nothing to re-run.

### Opting out

- `/statusline:statusline-teardown` removes the status line and leaves a marker so it is
  **not** reinstalled at the next session start.
- `/statusline:statusline-setup` runs the same install by hand (with dependency checks and
  visible output) and clears that marker.
- Set `CLAUDE_STATUSLINE_NO_AUTO_INSTALL=1` (for example under `env` in your
  settings) to stop the hook installing anything.

## Commands

| Command | Description |
|---------|-------------|
| `/statusline:statusline-setup` | Install the status line script and configure Claude Code |
| `/statusline:statusline-config` | View and edit status line configuration |
| `/statusline:statusline-teardown` | Remove status line from settings (`--clean` to also delete config) |

## Segments

The status line displays these segments (all configurable):

| Segment | Shows |
|---------|-------|
| `user` | Username (and hostname when over SSH) |
| `dir` | Name of the project the session started in (main repo name inside a git worktree) |
| `git` | Branch, staged/unstaged/untracked counts, ahead/behind |
| `model` | Active Claude model |
| `context` | Context window utilization: a bar that stretches to fill its column, plus % |
| `usage` | Session (5h) and weekly (7d) usage % with reset countdowns, condensed into one segment |
| `session` | Session API usage % with reset countdown |
| `weekly` | Weekly API usage % with reset countdown |
| `extra` | Monthly extra-credits usage (when applicable) |
| `cost` | Session cost in USD (hidden in subscription mode) |

## Configuration

Edit via `/statusline:statusline-config` or directly in `~/.config/claude-statusline/config.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `rows` | `[["user","dir","git"],["model","context","usage"],["extra","cost"]]` | Status line rows; each is an ordered list of segments. Rows with nothing to show are skipped |
| `segments` | — | Legacy single-row form, used only when `rows` is absent |
| `dir_style` | `"project"` | `project` (project name only) or `path` (abbreviated path, see `path_max_length`) |
| `align` | `true` | Pad segments so separators line up vertically across rows |
| `usage_extra` | `false` | Fold extra credits into the `usage` segment (appended as `· Ex $12.50/$50.00`) instead of showing a separate `extra` segment |
| `context_style` | `"bar"` | `bar` (fills its column, 8-24 cells), `icon` (`◔ 11%`) or `text` (`Ctx 11%`) |
| `context_bar_min` | `8` | Smallest context bar, in cells |
| `context_bar_max` | `24` | Largest a stretched context bar grows to; a value below the min is raised to it |
| `context_bar_default` | `10` | Bar size when it has no column to fill (last cell on a row, or `align: false`) |
| `session_icon` | `"◷"` | Icon for the 5-hour window in `usage`; `""` falls back to `5h` |
| `week_icon` | `"▦"` | Icon for the 7-day window in `usage`; `""` falls back to `7d` |
| `dir_icon` | `"⌂"` | Icon before the project name; `""` disables |
| `git_icon` | `"⎇"` | Icon before the branch name; `""` disables |
| `worktree_marker` | `"⧉"` | Replaces `dir_icon` inside a linked git worktree; `""` disables |
| `git_branch_max_length` | `40` | Ellipsize the middle of longer branch names; `0` disables |
| `separator` | `" \| "` | Separator between segments |
| `cache_ttl` | `300` | API usage cache TTL in seconds |
| `git_cache_ttl` | `5` | Git status cache TTL in seconds |
| `git_backend` | `"auto"` | `auto`, `daemon` (gitstatusd), or `cli` |
| `show_host` | `"auto"` | `auto` (SSH only), `always`, `never` |
| `cost_thresholds` | `[5, 20]` | Dollar thresholds for green/yellow/red coloring |
| `label_style` | `"short"` | `short` (Ctx/Ses/Wk) or `long` |

## Layout examples

Each example is the `config.json` that produces it, followed by what it renders.
Only the keys shown need to be present; everything else keeps its default.

### Default

No config needed. Two rows (a third appears while extra credits are in use, see
below), with the separators lined up and the context bar stretched to fill the
project column:

```text
stonefish  | ⌂ agent-toolkit | ⎇ feat/statusline-rows !1 ?1
Sonnet 5.5 | ▰▰▰▰▰▱▱▱▱▱▱ 43% | ◷ 4% 3h00m · ▦ 62% 2d0h
```

The bar is recomputed on every render, so a different project name gives a
different bar width (never below `context_bar_min` or above `context_bar_max`).

### Linked git worktree

Inside a linked worktree the project name is the main repo's name, followed by
`⧉`:

```text
stonefish  | ⌂ agent-toolkit⧉ | ⎇ feat/statusline-rows
Sonnet 5.5 | ▰▰▰▰▰▱▱▱▱▱▱▱ 43% | ◷ 4% 3h00m · ▦ 62% 2d0h
```

### Extra usage

The `extra` segment appears only while you have extra credits in use. By default
it gets a row of its own (alongside `cost`), which is skipped entirely when there
is nothing to show, so rows 1 and 2 never grow:

```text
stonefish  | ⌂ agent-toolkit | ⎇ feat/statusline-rows !1 ?1
Sonnet 5.5 | ▰▰▰▰▰▱▱▱▱▱▱ 43% | ◷ 4% 3h00m · ▦ 62% 2d0h
Ex $12.50/$50.00
```

To keep it to two rows, set `usage_extra` so extra credits are appended to the
`usage` segment as if they were part of it (the standalone `extra` segment is
then suppressed, so it can't show twice):

```json
{ "usage_extra": true }
```

```text
stonefish  | ⌂ agent-toolkit | ⎇ feat/statusline-rows !1 ?1
Sonnet 5.5 | ▰▰▰▰▰▱▱▱▱▱▱ 43% | ◷ 4% 3h00m · ▦ 62% 2d0h · Ex $12.50/$50.00
```

The cost is that row 2 then runs longer than row 1 while extra is active.

Or place `extra` anywhere yourself, for example inline as its own cell:

```json
{ "rows": [["user", "dir", "git"], ["model", "context", "usage", "extra"]] }
```

```text
stonefish  | ⌂ agent-toolkit | ⎇ feat/statusline-rows !1 ?1
Sonnet 5.5 | ▰▰▰▰▰▱▱▱▱▱▱ 43% | ◷ 4% 3h00m · ▦ 62% 2d0h | Ex $12.50/$50.00
```

Set `"extra_only_burning": true` to show it only once the session or weekly
window is at 100%.

### Long branch names

`git_branch_max_length` ellipsizes the middle, so the prefix and the tail
survive:

```json
{ "git_branch_max_length": 24 }
```

```text
⎇ feat/statusl…ug-handling
```

### Single row (legacy `segments`)

A flat `segments` array still works and renders one row. With no row above it,
the context bar uses `context_bar_default` (or the minimum, when mid-row):

```json
{ "segments": ["dir", "git", "model", "context", "usage"], "context_style": "icon" }
```

```text
⌂ agent-toolkit | ⎇ feat/statusline-rows !1 ?1 | Sonnet 5.5 | ◑ 43% | ◷ 4% 2h59m · ▦ 62% 1d23h
```

### Plain text, no icons

```json
{
  "context_style": "text",
  "label_style": "short",
  "dir_icon": "",
  "git_icon": "",
  "session_icon": "",
  "week_icon": "",
  "align": false
}
```

```text
stonefish | agent-toolkit | feat/statusline-rows !1 ?1
Sonnet 5.5 | Ctx 43% | 5h 4% ⟳2h59m · 7d 62% ⟳1d23h | Ex $12.50/$50.00
```

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | Config and API response parsing |
| `curl` | Yes | API usage polling |
| `git` | Yes | Branch and status info |
| `gitstatusd` | No | Faster git queries (falls back to `git status`) |

`gitstatusd` is auto-detected, in order, from `$GITSTATUS_DAEMON`, the
[gitstatus](https://github.com/romkatv/gitstatus) self-bootstrap cache
(`~/.cache/gitstatus/`), a Homebrew install (`brew install romkatv/gitstatus/gitstatus`),
and finally `PATH`. No configuration is needed if any of these is present.
