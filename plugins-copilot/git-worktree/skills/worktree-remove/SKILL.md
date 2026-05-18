---
name: worktree-remove
description: >-
  Remove a linked git worktree when parallel work is complete. Trigger when
  the user says "remove worktree", "delete worktree X", "clean up the
  worktree", "/worktree-remove", or finishes a feature and wants to tear
  down the parallel checkout. Optional `--delete-branch` also drops the
  branch; `--force` removes worktrees with uncommitted changes.
allowed-tools: shell
---

Remove a linked git worktree. Optionally delete its branch.

## Steps

1. Identify the target. The user can pass:
   - A slug name (e.g. `feature-auth`) — resolved under `.github/worktrees/`
   - An absolute path to the worktree directory

2. Check for uncommitted changes first:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-list.sh
   ```

3. If clean (or the user explicitly confirms), run:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name>
   ```

   To also delete the branch:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name> --delete-branch
   ```

   To force-remove when uncommitted changes exist:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <path-or-name> --force
   ```

4. Confirm removal to the user.

## Notes

- `--delete-branch` uses `git branch -d` (safe delete — fails if unmerged).
  Tell the user if the branch wasn't deleted and how to force-delete.
- `git worktree prune` runs automatically after removal.
