---
description: "Reset workspace to a clean state on the default branch"
allowed-tools: Bash
---

Reset the workspace to a clean state on the default branch. Use this between tasks or to abandon in-progress work.

### Steps

1. **Check for uncommitted work.** Run `git status --porcelain`. If there are uncommitted changes, warn the user and list the dirty files. Ask for confirmation before continuing — uncommitted work will be lost.

2. **Determine the default branch:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo default-branch
   ```

3. **Switch to the default branch and update:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch default
   git fetch --prune
   git pull
   ```

4. **Confirm.** Print the current branch and latest commit (`git log --oneline -1`).
