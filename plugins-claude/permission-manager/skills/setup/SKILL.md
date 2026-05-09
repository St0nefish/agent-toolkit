---
disable-model-invocation: true
name: setup
description: "Install shfmt and jq dependencies for the cmd-gate hook"
allowed-tools: Bash
---

# Setup

Install the required dependencies (`shfmt`, `jq`) for the cmd-gate classification hook.

The cmd-gate hook blocks all Bash commands until these are installed. This command is allowed through the hook via a bootstrap bypass so it can recover from that state.

## Instructions

Run the setup script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-deps.sh
```

Report the result to the user. If installation fails, show the manual install links from the script output.
