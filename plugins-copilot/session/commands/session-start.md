---
description: "Show available work and pick something to start"
allowed-tools: Bash, AskUserQuestion
---

Generic entry point. Shows available work and lets the user pick what to focus on.

### Steps

1. Gather current state:
   - current branch
   - default branch
   - uncommitted changes
   - recent commits
   - whether the current branch already maps to a linked issue

2. Collect the two sources of available work:

   **Open issues** (unstarted work) — on GitHub repos, prefer
   `gh issue list --limit 20 --state open --json number,title,labels,milestone,comments,createdAt`.
   Use the equivalent host-native issue command on other platforms when available.

   **Active branches** (in-progress work) — branches not yet merged to the default branch, sorted by most recent commit:
   - determine the default branch directly from git
   - list unmerged branches sorted by most recent commit
   - compute total, merged, and unmerged branch counts

3. **Present the options.** Build a numbered list combining both sources:
   - Issues displayed as: `[issue] #N — <title>` (show at most 10)
   - Branches displayed as: `[branch] <branch>` (show top 10 unmerged by recency)
   - Branch summary line: `N branches total (M merged, K unmerged)`. If more than 10 unmerged branches exist, note how many are hidden.
   - Always include a final option: `[new] Describe what you want to work on`

   Use AskUserQuestion with this combined list as choices.

4. **Act on the selection:**

   - **Issue selected** — fetch the full issue, choose the branch prefix from labels, then **create the branch via step 4a** (in place or worktree) using base name `<type>/<N>-<slug>`, and continue with the issue context
   - **Branch selected** — switch to that branch if needed, then follow the `resume` flow from the context-building step onward (step 4a does not apply)
   - **Freeform selected** — ask the user to describe the task, then **create the branch via step 4a** using base name `wip/<kebab-slug>`. No issue is linked; proceed with the free-form task description as context

4a. **Isolate in a worktree? (new work only — assumes the `git-worktree` plugin is installed.)** Skip when resuming an existing branch or when already inside a worktree (`git worktree list` shows you are not in the main worktree).

   Default to a worktree for substantial new work — it keeps the main checkout clean and lets parallel work coexist. Lean toward one when the current branch has uncommitted changes, the user asked for parallel/isolated work, or the work is a non-trivial feature. Create the branch **in place** for trivial one-file fixes. If genuinely unsure, offer the choice via AskUserQuestion (Worktree / In place).

- **In place:** `git switch -c <base-name>`.
- **Worktree (via the `git-worktree` plugin):** create it with the plugin's `worktree-create` flow — `git worktree add .github/worktrees/<slug> -b <base-name>` (the base dir is auto-gitignored on first use; slug = the branch name with `/` and other non-`[A-Za-z0-9._-]` chars replaced by `-`). Then run **all** subsequent steps from inside the worktree by prefixing commands with `cd .github/worktrees/<slug> && …`; the plugin's whitelist hook auto-approves operations on the worktree path. A fresh worktree is a clean checkout — reinstall or symlink heavy gitignored deps (e.g. `node_modules`, `.venv`) if the work needs them.

5. Confirm the starting context to the user:

- Branch name (new or existing)
- Linked issue number and title (if any)
- First suggested steps based on context
