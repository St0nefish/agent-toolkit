---
description: "Install and configure the status line"
allowed-tools: Bash
disable-model-invocation: true
---

# Status Line Setup

Install the claude-statusline script, check dependencies, and configure Claude Code's `statusLine` setting.

The script is copied to `~/.config/claude-statusline/statusline.sh` (a version-stable location) and `~/.claude/settings.json` is patched to point there.

## Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

Report the result to the user. If any dependencies are missing, show the install hints from the output.

If setup succeeds, let the user know they need to restart Claude Code or start a new session for the status line to appear.
