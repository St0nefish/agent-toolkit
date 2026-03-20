# Statusline

Configurable status line for Claude Code showing git status, model, context usage, API utilization, and session cost with ANSI colors.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/statusline
```

Then run setup:

```text
/statusline:setup
```

This copies the status line script to `~/.config/claude-statusline/` and patches your Claude Code settings to use it.

## Commands

| Command | Description |
|---------|-------------|
| `/statusline:setup` | Install the status line script and configure Claude Code |
| `/statusline:config` | View and edit status line configuration |
| `/statusline:teardown` | Remove status line from settings (`--clean` to also delete config) |

## Segments

The status line displays these segments (all configurable):

| Segment | Shows |
|---------|-------|
| `user` | Username (and hostname when over SSH) |
| `dir` | Current directory (truncated) |
| `git` | Branch, staged/unstaged/untracked counts, ahead/behind |
| `model` | Active Claude model |
| `context` | Context window utilization % |
| `session` | Session API usage % with reset countdown |
| `weekly` | Weekly API usage % with reset countdown |
| `extra` | Monthly extra-credits usage (when applicable) |
| `cost` | Session cost in USD (hidden in subscription mode) |

## Configuration

Edit via `/statusline:config` or directly in `~/.config/claude-statusline/config.json`:

| Key | Default | Description |
|-----|---------|-------------|
| `segments` | all 9 | Which segments to show, in order |
| `separator` | `" \| "` | Separator between segments |
| `cache_ttl` | `300` | API usage cache TTL in seconds |
| `git_cache_ttl` | `5` | Git status cache TTL in seconds |
| `git_backend` | `"auto"` | `auto`, `daemon` (gitstatusd), or `cli` |
| `show_host` | `"auto"` | `auto` (SSH only), `always`, `never` |
| `cost_thresholds` | `[5, 20]` | Dollar thresholds for green/yellow/red coloring |
| `label_style` | `"short"` | `short` (Ctx/Ses/Wk) or `long` |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | Config and API response parsing |
| `curl` | Yes | API usage polling |
| `git` | Yes | Branch and status info |
| `gitstatusd` | No | Faster git queries (falls back to `git status`) |
