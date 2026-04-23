---
description: "Create a git worktree for parallel agentic work"
allowed-tools: Bash
---

Create a new linked git worktree in a sibling directory (`../<repo>-worktrees/<branch-slug>`).
The worktree gets its own branch so work is isolated from the current checkout.

## Steps

1. Run the create script with the branch name the user provided:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <branch-name>
   ```

   If the user specified a base branch (e.g. "from main"), pass it:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <branch-name> --from <base-branch>
   ```

2. Report the worktree path and branch to the user.

3. Explain that the worktree plugin's preToolUse hook will auto-allow operations
   targeting that path — no manual permission steps are needed.

4. Remind the user to run `/worktree:remove` or call `worktree-remove.sh` when done.

## Notes

- If the branch already exists, the worktree checks it out without creating a new branch.
- The base directory (`../<repo>-worktrees/`) is created automatically if it doesn't exist.
- Override the base directory by setting `WORKTREE_BASE_DIR` in the environment.
