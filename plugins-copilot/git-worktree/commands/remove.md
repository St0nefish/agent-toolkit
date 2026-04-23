---
description: "Remove a git worktree when parallel work is complete"
allowed-tools: Bash
---

Remove a linked git worktree. Optionally deletes the branch as well.

## Steps

1. Determine what the user wants to remove. They can specify:
   - A slug name (e.g. `feature-auth`) — looked up under `../<repo>-worktrees/`
   - An absolute path to the worktree directory

2. Check if the worktree has uncommitted changes first:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-list.sh
   ```

3. If clean (or user confirms), run:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name>
   ```

   To also delete the branch:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name> --delete-branch
   ```

   If the worktree has uncommitted changes and user explicitly confirms force-removal:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name> --force
   ```

4. Confirm removal to the user.

## Notes

- `--delete-branch` uses `git branch -d` (safe delete — fails if branch is unmerged).
  Tell the user if the branch was not deleted and how to force-delete if needed.
- `git worktree prune` runs automatically after removal to clean up stale metadata.
