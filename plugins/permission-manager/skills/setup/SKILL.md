---
name: permission-setup
description: >-
  Install shfmt and jq dependencies required by the bash-safety hook.
  Detects OS and package manager, then installs missing tools.
  Run this if bash-safety blocks commands with a missing dependencies message.
disable-model-invocation: true
allowed-tools: Bash
---

# permission-setup

Install the required dependencies for the bash-safety hook.

## Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-deps.sh
```

Report the result to the user. If installation fails, show the manual install links from the script output.
