# Statusline

A status line for Claude Code built as a **mod**: a hooks module that gathers
everything natively and draws one coloured line. Version 3 replaces the old
1,000-line bash renderer, with its `curl` polling, usage cache and git cache.

```text
  stonefish  ⌂ agent-toolkit  ⑂ feat/statusline-v3 !2  ✦ Sonnet 5.5  ▰▰▰▱▱▱▱▱▱▱ 33%  ◷ 12% 3h26m  ▦ 86% 1d1h
```

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/statusline
```

That's it. Start a new session and the line appears from the session after
that. Claude Code plugins can't set `statusLine` themselves, so a
`SessionStart` hook does the setup for you the first time it runs:

- It copies a tiny stub (`statusline.sh`) to `~/.config/claude-statusline/` and
  adds `statusLine` to `~/.claude/settings.json`.
- It is **add-only**: if your settings already define a `statusLine` (yours or
  another tool's), nothing is written.
- It is silent.

### How it works

A mod can draw coloured text above the prompt but not under it, and the
`statusLine` slot is the one place that draws coloured text under the prompt.
So the work is split:

- **The mod** (`hooks/register.tsx`) reads git, context, usage windows, cost and
  extra credits, and writes the finished ANSI line to
  `~/.cache/claude-statusline/<session-id>`.
- **The stub** (`scripts/statusline.sh`) reads the session id from the JSON
  Claude Code passes it and prints that file. It polls nothing, caches nothing
  and needs no `jq`.

### Updates

The same hook keeps the installed stub current. After `claude plugin update`
the new stub is live from your next session start. Files are swapped in
atomically. Upgrading from a version before 3.0 replaces the old bash renderer
with the stub automatically; an old `config.json` is left alone but no longer
read.

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
| `/statusline:statusline-setup` | Install the stub and configure Claude Code's `statusLine` |
| `/statusline:statusline-config` | Show how to choose a style |
| `/statusline:statusline-teardown` | Remove the status line (`--clean` to also delete the stub and cache) |

## Options

Defaults are the standard setup; use `/statusline:statusline-config` only to override.

| Option | Default | Effect |
|--------|---------|--------|
| `style` | `below` | Where and how the line is drawn (see `/statusline:statusline-config`) |
| `gitPollSeconds` | `3` | Idle re-check of git for changes made elsewhere; `0` turns it off |
| `segmentGap` | `1` | Spaces between segments; `2` spreads them out on wide terminals |
| `leftPad` | `2` | Spaces before the first segment in the `below` style; `0` is flush left |

The `statusLine` entry the installer writes sets `refreshInterval` to 3 seconds so
Claude Code re-reads the line while the session is idle. The entry is added at session
start whenever settings have none. The plugin's own entry gets `refreshInterval` filled
in if it lacks one; a value you set, or an entry that is not the plugin's, is never edited.

## What it shows

| Segment | Shows |
|---------|-------|
| user | Username, `user@host` over SSH, bright yellow as root |
| project | Project name (the main repo's name inside a linked worktree, marked `⧉`) |
| branch | Branch with the git-branch glyph, always green, ellipsized in the middle when long |
| git chips | `⇣` behind and `⇡` ahead (green), `+` staged and `!` modified (yellow), `?` untracked (blue), in Powerlevel10k's order |
| model | Friendly name (`Sonnet 5.5`), not the model id |
| context | Fill bar and percentage |
| limits | 5h (`◷`) and 7d (`▦`) usage with reset countdowns |
| extra | `⊕ $used/$limit` monthly extra credits, shown only once you have spent some |
| cost | Session cost, only when no rate limits are reported |

Severity colours follow Claude Code's own `success`, `warning` and `error`;
the rest are colour names (`yellow`, `green`, `blueBright`), so everything
follows your terminal palette and theme rather than fixed values.

## Styles

Choose one with `/config` (or `claude plugin configure statusline@agent-toolkit`).

| Style | Where | Notes |
|-------|-------|-------|
| `below` (default) | Under the prompt | Coloured, via the `statusLine` slot; needs the stub installed |
| `flat-left` | Above the prompt | Flat text packed left; works with no `statusLine` setup |
| `powerline` | Above the prompt | One dark band with Nerd Font arrows |
| `plain` | Above the prompt | Coloured text with thin bars; no patched font needed |

If another tool already owns your `statusLine`, the stub is not installed and
`below` shows nothing; pick `flat-left` instead.

## Data sources

Context, usage windows and cost come from the session itself
(`session.measure`). Extra credits are not part of that data, so they are read
from the OAuth usage endpoint at most every 5 minutes, using the session's own
credential; the plugin never reads a token. Git status is read with
`git status --porcelain=v2` after each Bash call and each turn.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `git` | Yes | Branch and status info |
| `jq` | Install only | Editing `settings.json` (the stub itself does not need it) |
