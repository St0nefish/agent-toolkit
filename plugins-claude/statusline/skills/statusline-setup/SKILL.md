---
disable-model-invocation: true
name: statusline-setup
description: "Install and configure the status line"
allowed-tools: Bash
---

# Status Line Setup

Install the claude-statusline stub, check dependencies, and configure Claude Code's `statusLine` setting.

The status line itself is drawn by the plugin's mod, which writes the finished line to a per-session file. The stub is a few lines of shell that print that file. It is copied to `~/.config/claude-statusline/statusline.sh` (a version-stable location) and `~/.claude/settings.json` is patched to point there.

## Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

Report the result to the user. If any dependencies are missing, show the install hints from the output.

If setup succeeds, let the user know they need to restart Claude Code or start a new session for the status line to appear.

The plugin also installs and refreshes the status line by itself at session start, so this command is only needed to repair an install, re-enable it after `/statusline:statusline-teardown`, or see the dependency checks.
