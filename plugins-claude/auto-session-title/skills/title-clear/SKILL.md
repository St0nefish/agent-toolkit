---
name: title-clear
description: "Clear the per-worktree session-title override so the title reverts to <repo>:<branch> on the next prompt."
when_to_use: "Use when the user wants to drop a custom title set with title-set or go back to branch-based naming."
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
