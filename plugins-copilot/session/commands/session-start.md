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

   - **Issue selected** — fetch the full issue, choose the branch prefix from labels, create a local branch with `git switch -c`, and continue with the issue context
   - **Branch selected** — switch to that branch if needed, then follow the `resume` flow from the context-building step onward
   - **Freeform selected** — ask the user to describe the task, then:
     - Create and switch to a `wip/<kebab-slug>` branch with `git switch -c`
     - No issue is linked; proceed with the free-form task description as context

5. Confirm the starting context to the user:
   - Branch name (new or existing)
   - Linked issue number and title (if any)
   - First suggested steps based on context
