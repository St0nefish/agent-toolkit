---
name: worktree-list
description: >-
  List all active git worktrees for the current repository, including path,
  branch, and working-tree status. Trigger when the user asks "list worktrees",
  "show worktrees", "what worktrees do I have", or wants to see active
  parallel checkouts before creating or removing one.
allowed-tools: shell
---

Run the list script and present its output verbatim. The script formats a
table with PATH, BRANCH, and STATUS columns.

```bash
bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-list.sh
```

If no worktrees exist, suggest `/worktree-create <branch-name>` to create one.
