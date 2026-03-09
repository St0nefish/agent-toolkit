---
description: "Remove the status line"
allowed-tools: Bash, AskUserQuestion
disable-model-invocation: true
---

# Status Line Teardown

Remove the claude-statusline configuration from Claude Code.

## Instructions

1. Ask the user whether they also want to remove the config and cache files (a full clean), or just disable the status line (keeping config for later re-setup). Use `AskUserQuestion`.

2. Run the teardown script with the appropriate flags:

   To disable only (keep config and cache):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/teardown.sh
   ```

   To fully clean (remove config, cache, and installed script):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/teardown.sh --clean
   ```

3. Report the result. Let the user know they need to restart Claude Code or start a new session for the change to take effect.
