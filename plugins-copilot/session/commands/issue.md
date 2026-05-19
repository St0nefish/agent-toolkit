---
description: "Select an open issue and begin work on it"
allowed-tools: Bash, AskUserQuestion
---

Select an open issue and begin work on it.

### Steps

1. Fetch open issues with native host tooling:
   - on GitHub repos, prefer `gh issue list --limit 20 --state open --json number,title,labels,milestone,comments,createdAt`
   - on other hosts, use the equivalent host-native issue command if available

2. **Rank and select.** From the returned JSON array, pick the top 3 by priority:
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments -> higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   Display the top 3 as choices and use AskUserQuestion. Include issue number, title, and labels for each choice.

3. Fetch the full issue details and recent discussion for the selected issue.

4. **Determine branch type** from issue labels:
   - `bug`, `fix` -> `bug/`
   - `enhancement`, `feature`, `improvement` -> `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` -> `chore/`
   - No matching label -> `feature/`

5. **Create the branch.** Generate a kebab-case slug (3-5 words) from the issue title,
   then create and switch to `<type>/<N>-<slug>` with `git switch -c` (or the
   equivalent `git checkout -b` fallback on older Git versions).

6. Confirm to the user:
   - Branch created
   - Issue title and body summary
   - Suggested first implementation steps based on the issue description
