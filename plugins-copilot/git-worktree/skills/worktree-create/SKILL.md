---
name: worktree-create
description: >-
  Create a new linked git worktree on its own branch under
  `.github/worktrees/<branch-slug>` for parallel agentic work. Trigger when
  the user says "create a worktree", "new worktree for X", "make a worktree
  on branch Y", "spin up a parallel checkout", or "/worktree-create".
  Supports an optional base branch via `--from <branch>`.
allowed-tools: shell
---

Create a new linked git worktree. Keeping worktrees inside the repo
(`.github/worktrees/`, auto-gitignored on first use) keeps operations
against them inside the session's CWD scope.

## Steps

1. Run the create script with the branch name the user provided:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <branch-name>
   ```

   If the user specified a base branch ("from main"), pass it:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <branch-name> --from <base-branch>
   ```

2. Report the worktree path and branch back to the user.

3. Remind them to run `/worktree-remove <name>` when finished.

## Notes

- If the branch already exists, the worktree checks it out without creating
  a new one.
- The base directory (`.github/worktrees/`) is created automatically and
  added to `.gitignore` on first use.
- Override the base directory with `WORKTREE_BASE_DIR` (skips the
  auto-gitignore step).
