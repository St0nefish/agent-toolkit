---
name: title-clear
description: "Clear the session-title override — title reverts to <repo>:<branch>"
disable-model-invocation: true
allowed-tools: Bash
---

Remove the per-worktree session-title override file so the hook falls back to branch-derived naming.

### Steps

1. Delete the override file if it exists:

   ```bash
   GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) || { echo "Not in a git repo"; exit 1; }
   rm -f "$GIT_DIR/claude-session-title"
   ```

2. Confirm in one line: override cleared, title will revert to `<repo>:<branch>` on the next user prompt.
