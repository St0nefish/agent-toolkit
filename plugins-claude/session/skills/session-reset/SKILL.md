---
disable-model-invocation: true
name: session-reset
description: "Reset workspace to a clean state on the default branch"
allowed-tools: Bash, ExitWorktree, AskUserQuestion
---

Reset the workspace to a clean state on the default branch. Use this between tasks or to abandon in-progress work.

### Steps

1. **Check for uncommitted work.** Run `git status --porcelain`. If there are uncommitted changes, warn the user and list the dirty files. Ask for confirmation before continuing — uncommitted work will be lost.

2. **Determine the default branch:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo default-branch
   ```

3. **Leave any worktree first.** If this session is in a worktree (entered via `EnterWorktree` this session), call `ExitWorktree action: keep` to return to the main checkout — this preserves the branch and worktree. Only use `action: remove` (with `discard_changes: true` if needed) when the user explicitly wants that worktree and its work destroyed. If `ExitWorktree` no-ops (worktree from an earlier session), `cd` to the main worktree root (first entry of `git worktree list`) instead.

4. **Switch to the default branch and update** (in the main checkout):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch default
   git fetch --prune
   git pull
   ```

5. **Confirm.** Print the current branch and latest commit (`git log --oneline -1`).
