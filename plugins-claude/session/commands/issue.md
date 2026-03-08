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
   > bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue list --limit 20 --state open
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
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>
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

6. **Confirm branch and issue.** Tell the user:
   - Branch created
   - Issue title and one-line body summary

7. **Explore the codebase.** Launch 2-3 Agents **in parallel** (subagent_type: Explore) to investigate the issue. Design each agent's prompt based on what the issue describes — for example:

   - **Agent A — locate the code:** search for files, functions, types, or modules mentioned in or implied by the issue. Read them and report what each does, where the problem likely lives, and relevant surrounding code.
   - **Agent B — find related tests/config:** search for existing tests, related config, CI setup, or documentation that covers the affected area. Report what exists and what's missing.
   - **Agent C — trace the flow** (if relevant): follow the call chain or data flow through the area the issue describes. Report entry points, dependencies, and edge cases.

   Tailor the agents to the specific issue — not every issue needs all three. A documentation issue might only need one agent. A cross-cutting bug might need three.

   Each agent prompt must include the full issue title, body, and labels so it has context for what to look for. If an agent needs to interact with the issue tracker or repository API, it must use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never call `gh`, `tea`, or other platform CLIs directly.

8. **Synthesize a plan.** Once all agents return, combine their findings into a concrete implementation plan:
   - List the specific files and line ranges that need changes
   - Describe what each change should do (not just "fix the bug" — say *how*)
   - Note any tests to add or update
   - Flag risks, edge cases, or questions that need the user's input

   Present the plan to the user as the starting point for work.
