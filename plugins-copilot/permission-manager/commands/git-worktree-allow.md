---
description: "Allow git-worktree extension tools for this repo"
argument-hint: "[repo-path]"
allowed-tools: Bash
disable-model-invocation: true
---

# Allow git-worktree

Persist Copilot approvals for the `git-worktree` user extension and its `sf_git_worktree_*` tools.

- With no argument, seed approvals for the current repo root (or current directory if not in a git repo)
- With an argument, seed approvals for that repo path instead

## Instructions

Run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/seed-copilot-git-worktree-permissions.sh $1
```

Then show the output to the user.
