---
description: "Show available work and pick something to start"
allowed-tools: Bash
---

Generic entry point. Shows available work and lets the user pick what to focus on.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Collect the two sources of available work:

   **Open issues** (unstarted work):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue list --limit 20 --state open
   ```

   **Active branches** (in-progress work) — branches not yet merged to the default branch:

   ```bash
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools repo default-branch)
   git --no-pager branch --no-merged "$DEFAULT" --format '%(refname:short)' 2>/dev/null
   ```

3. **Present a summary.** Display a concise overview of available work:
   - Issues as: `#N — <title>` (show at most 10)
   - Active branches as: `<branch>` (show at most 5)

   Then tell the user they can pick an issue number, branch name, or describe something new. **Do not use AskUserQuestion** — just print the summary and wait for the user to type a response in the normal chat input.

4. **Act on the user's response:**

   - **Issue number mentioned** (e.g. "#42" or "42") — follow the `issue` action from step 3 onward (branch creation), skipping the list/pick steps
   - **Branch name mentioned** — follow the `resume` action from step 2 onward (context extraction), skipping the list/pick step
   - **Freeform description** — create a `wip/<kebab-slug>` branch: `git checkout -b wip/<slug>`. No issue is linked; proceed with the user's description as context.

5. Confirm the starting context to the user:
   - Branch name (new or existing)
   - Linked issue number and title (if any)
   - First suggested steps based on context
