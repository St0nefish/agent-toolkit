---
description: "Resume work on an existing in-progress branch"
allowed-tools: Bash, Read, AskUserQuestion
---

Resume work on an existing in-progress branch.

### Steps

1. List active branches (not merged to default):
   determine the default branch directly from git, then list local branches not
   yet merged into it.

2. If more than one branch exists, use AskUserQuestion to let the user pick. If only one, proceed with it automatically.

3. Check out the selected branch if not already on it:
   use `git switch <branch>` (or `git checkout <branch>` on older Git versions).

4. Gather context from multiple sources in parallel:
   - current branch state, commits ahead of default, uncommitted changes, and recent commits
   - changed files from committed and uncommitted work

   **If the branch name matches `type/NNN-*`**, extract the issue number and fetch it:
   - on GitHub repos, prefer `gh issue view <N> --json title,body,state,comments,labels,url`
   - otherwise use the equivalent host-native issue command if available

   **Check for a WIP/handoff commit** — search recent commits for one with `=== IN PROGRESS ===` in the body:

   ```bash
   git --no-pager log --max-count=5 --format="%H %s" | grep -i "^[^ ]* WIP:"
   ```

   If found, extract the body: `git --no-pager show <sha> --format=%B --no-patch`

5. Build and present the resume context:
   - **Branch:** name, commits ahead of default, uncommitted changes
   - **Linked issue:** title, body excerpt, recent comments (if any)
   - **In progress** (from WIP commit `=== IN PROGRESS ===` section, if present)
   - **Next steps** (from WIP commit `=== NEXT STEPS ===` section or last issue comment, if present)
   - **Key context** (from WIP commit `=== KEY CONTEXT ===` section, if present)
   - **Recent commits:** last 3 subjects

6. Suggest the most logical next action based on the context. Ask the user if they want to proceed or adjust the plan.
