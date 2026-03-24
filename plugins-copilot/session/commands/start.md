---
description: "Show available work and pick something to start"
allowed-tools: Bash, AskUserQuestion
---

Generic entry point. Shows available work and lets the user pick what to focus on.

### Steps

1. Gather current state:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup
   ```

2. Collect the two sources of available work:

   **Open issues** (unstarted work):

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue list --limit 20 --state open
   ```

   **Active branches** (in-progress work) — branches not yet merged to the default branch, sorted by most recent commit:

   ```bash
   DEFAULT=$(bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo default-branch)
   # Unmerged branches sorted by most recent commit (top 10)
   git --no-pager branch --no-merged "$DEFAULT" \
     --sort=-committerdate \
     --format '%(refname:short)' 2>/dev/null | head -10
   # Branch summary counts
   TOTAL=$(git --no-pager branch --format '%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
   MERGED=$(git --no-pager branch --merged "$DEFAULT" --format '%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
   UNMERGED=$(git --no-pager branch --no-merged "$DEFAULT" --format '%(refname:short)' 2>/dev/null | wc -l | tr -d ' ')
   ```

3. **Present the options.** Build a numbered list combining both sources:
   - Issues displayed as: `[issue] #N — <title>` (show at most 10)
   - Branches displayed as: `[branch] <branch>` (show top 10 unmerged by recency)
   - Branch summary line: `N branches total (M merged, K unmerged)`. If more than 10 unmerged branches exist, note how many are hidden.
   - Always include a final option: `[new] Describe what you want to work on`

   Use AskUserQuestion with this combined list as choices.

4. **Act on the selection:**

   - **Issue selected** — follow the `issue` action from step 3 onward (branch creation), skipping the list/pick steps
   - **Branch selected** — follow the `resume` action from step 2 onward (context extraction), skipping the list/pick step
   - **Freeform selected** — ask the user to describe the task, then:
     - Create a `wip/<kebab-slug>` branch: `bash ${COPILOT_PLUGIN_ROOT}/scripts/branch create wip/<slug>`
     - No issue is linked; proceed with free-form task description as context

5. Confirm the starting context to the user:
   - Branch name (new or existing)
   - Linked issue number and title (if any)
   - First suggested steps based on context
