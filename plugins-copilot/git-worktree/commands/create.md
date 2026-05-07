---
description: "Create a git worktree for parallel agentic work"
allowed-tools: Bash
---

Create a new linked git worktree under `.github/worktrees/<branch-slug>` inside
the repo (auto-gitignored on first use). Keeping worktrees in-repo lets the
harness's working-directory permission scope cover them, so operations against
them don't trigger per-path approval prompts. The worktree gets its own branch
so work is isolated from the current checkout.

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
- The base directory (`.github/worktrees/`) is created automatically and added
  to `.gitignore` on first use.
- Override the base directory by setting `WORKTREE_BASE_DIR` in the environment
  (skips the auto-gitignore step).
