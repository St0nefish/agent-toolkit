---
description: "Reset workspace to a clean state on the default branch"
allowed-tools: Bash
---

Reset the workspace to a clean state on the default branch. Use this between tasks or to abandon in-progress work.

### Steps

1. **Check for uncommitted work.** Run `git status --porcelain`. If there are uncommitted changes, warn the user and list the dirty files. Ask for confirmation before continuing — uncommitted work will be lost.

2. **Determine the default branch.** Prefer `origin/HEAD` if available:

   ```bash
   git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||'
   ```

   If that fails, fall back to `main` or `master` (whichever exists locally).

3. **Leave any worktree first.** If you are inside a worktree (under `.github/worktrees/`), `cd` to the main worktree root (first entry of `git worktree list`) before switching branches — this leaves the worktree and its branch intact. Only remove it (via the `git-worktree` plugin's `worktree-remove` flow) if the user explicitly wants that work discarded.

4. **Switch to the default branch and update** (in the main checkout):

   ```bash
   git checkout <default-branch>
   git fetch --prune
   git pull
   ```

5. **Confirm.** Print the current branch and latest commit (`git log --oneline -1`).
