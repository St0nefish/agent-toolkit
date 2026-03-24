# Notify on Stop

Desktop notification when Claude finishes a long-running task. Useful when you switch to another window while waiting.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/notify-on-stop
```

## How It Works

Records the time when you submit a prompt. When Claude stops, if the elapsed time exceeds the threshold, a native desktop notification fires with the project name and a preview of the response.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_NOTIFY_MIN_SECONDS` | `30` | Minimum seconds before a notification fires |

## Platform Support

| Platform | Notification method |
|----------|-------------------|
| macOS | `osascript` (native notification center) |
| Linux | `notify-send` |
| WSL | `notify-send` with fallback to PowerShell toast |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `jq` | Yes | Hook payload parsing |
| `osascript` / `notify-send` | Yes | Platform notification (one of these) |
