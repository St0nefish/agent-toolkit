# Notify on Stop

Desktop notification when Claude finishes a long-running task. Useful when you switch to another window while waiting.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/notify-on-stop
```

## How It Works

Records the time when you submit a prompt. When Claude stops, if the elapsed time exceeds the threshold, a native desktop notification fires with the project name and a preview of the response.

## Input Needed

If the `inbox` plugin is installed and the session has open (parked) questions when Claude stops, and no background tasks are still running, a notification titled "Input needed" fires immediately with the project name and the number of questions awaiting you. This bypasses the `CLAUDE_NOTIFY_MIN_SECONDS` threshold. Only questions count: pending decisions in the inbox never trigger a notification. Without the `inbox` plugin there are never any open questions, so this is a no-op and the normal behavior applies.

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
