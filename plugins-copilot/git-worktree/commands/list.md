---
description: "List all active git worktrees for the current repo"
allowed-tools: Bash
---

Show all linked git worktrees for the current repository, including their path,
branch, and working-tree status.

## Steps

1. Run:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-list.sh
   ```

2. Present the output to the user as-is. The script formats a table with PATH,
   BRANCH, and STATUS columns.

3. If no worktrees exist, suggest `/worktree:create <branch-name>` to create one.
