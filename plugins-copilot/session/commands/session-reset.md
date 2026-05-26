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

3. **Switch to the default branch and update:**

   ```bash
   git checkout <default-branch>
   git fetch --prune
   git pull
   ```

4. **Confirm.** Print the current branch and latest commit (`git log --oneline -1`).
