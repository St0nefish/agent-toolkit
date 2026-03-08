---
description: "Select an open issue and begin work on it"
allowed-tools: Bash, AskUserQuestion
---

Select an open issue and begin work on it.

### Steps

1. Fetch open issues:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue list --limit 20 --state open
   ```

2. **Rank and select.** From the returned JSON array, pick the top 3 by priority:
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments → higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   Display the top 3 as choices and use AskUserQuestion. Include issue number, title, and labels for each choice.

3. Fetch the full issue:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue show <N>
   ```

4. **Determine branch type** from issue labels:
   - `bug`, `fix` → `bug/`
   - `enhancement`, `feature`, `improvement` → `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore/`
   - No matching label → `feature/`

5. **Create the branch.** Generate a kebab-case slug (3-5 words) from the issue title:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/branch create <type>/<N>-<slug>
   ```

   Example: issue #42 "Fix login crash on empty password" → `bug/42-fix-login-crash`

6. Confirm to the user:
   - Branch created
   - Issue title and body summary
   - Suggested first implementation steps based on the issue description
