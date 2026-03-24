# Image

Clipboard paste and screenshot capture. Model-triggered — fires when you mention pasting an image or viewing a screenshot.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/image
```

## Skills

| Skill | Triggers on | What it does |
|-------|-------------|--------------|
| `paste` | "paste", "clipboard image" | Reads image from clipboard, saves to `/tmp/clip_<hash>.png` (deduplicated by content hash) |
| `screenshot` | "screenshot", "latest screenshot" | Finds the newest `.png` in your screenshots directory |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SCREENSHOTS_DIR` | `~/Pictures/Screenshots` (macOS/Linux), `/mnt/c/Users/<USER>/Pictures/Screenshots` (WSL) | Screenshots directory |

## Dependencies

| Tool | Platform | Purpose |
|------|----------|---------|
| `pngpaste` | macOS | Clipboard read (`brew install pngpaste`) |
| `wl-paste` | Linux (Wayland) | Clipboard read |
| `xclip` | Linux (X11) | Clipboard read |
| PowerShell | WSL | Clipboard read (built-in) |
