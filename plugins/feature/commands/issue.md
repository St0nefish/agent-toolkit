---
description: "Select an open issue and begin work on it"
allowed-tools: Agent, Bash, AskUserQuestion
---

Select an open issue and begin work on it.

### Steps

1. **Fetch and rank issues using a subagent.** Launch an Agent (subagent_type: general-purpose) with the following prompt:

   > Fetch open issues and return the top 3 by priority.
   >
   > Run this command:
   >
   > ```bash
   > bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue list --limit 20 --state open
   > ```
   >
   > From the returned JSON array, rank by priority using these criteria:
   > - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   > - Issues with a milestone set rank higher than those without
   > - More comments → higher priority (community signal)
   > - Older issues rank higher than newer (age as proxy for neglect)
   >
   > Return ONLY the top 3 issues. For each, include: number, title, and labels (comma-separated). Format each as a single line:
   > `#N — Title [label1, label2]`

2. **Present the top 3.** Use AskUserQuestion with the agent's results as choices. Each option label should be `#N — Title` and the description should list the labels.

3. Fetch the full issue:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N>
   ```

4. **Determine branch type** from issue labels:
   - `bug`, `fix` → `bug/`
   - `enhancement`, `feature`, `improvement` → `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore/`
   - No matching label → `feature/`

5. **Create the branch.** Generate a kebab-case slug (3-5 words) from the issue title:

   ```bash
   git checkout -b <type>/<N>-<slug>
   ```

   Example: issue #42 "Fix login crash on empty password" → `bug/42-fix-login-crash`

6. Confirm to the user:
   - Branch created
   - Issue title and body summary
   - Suggested first implementation steps based on the issue description
