---
description: "Select an open issue and begin work on it"
allowed-tools: Agent, Bash, AskUserQuestion, EnterPlanMode
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

6. **Confirm branch and issue briefly.** Print two lines only — the branch name and the issue title. Do NOT print suggested steps, do NOT print file locations, do NOT say "want me to start?" — proceed immediately to step 7.

7. **Explore the codebase — this step is mandatory.** Immediately launch 2-3 Agents **in parallel** (subagent_type: Explore) to investigate the issue. Do not skip this step. Do not summarize the issue and ask the user what to do — the agents must run now.

   Design each agent's prompt to answer a specific question about the codebase. Include the full issue title, body, and labels in every agent prompt so each has full context. Tell each agent to read the actual source files and report concrete findings (file paths, line numbers, code snippets, function signatures).

   Agent prompts to choose from (pick 2-3 based on the issue):

   - **Locate the code:** Find the files, functions, types, or modules mentioned in or implied by the issue. Read them fully. Report: what each does, where the problem or change point is, relevant surrounding code and function signatures.
   - **Find tests and related config:** Search for existing tests covering the affected area, related configuration, CI setup, or documentation. Report: what test coverage exists, what's missing, how the test suite is structured.
   - **Trace the data/call flow:** Follow the call chain or data flow through the area the issue describes. Report: entry points, intermediate steps, dependencies, and edge cases.

   If an agent needs to interact with the issue tracker or repository API, it must use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never call `gh`, `tea`, or other platform CLIs directly.

8. **Enter plan mode.** After all agents return, call `EnterPlanMode`. Using the agents' findings, produce a concrete implementation plan:
   - List the specific files and line ranges that need changes
   - Describe what each change should do and how (not "fix the bug" — describe the actual code change)
   - Note any tests to add or update
   - Flag risks, edge cases, or open questions

   Present the plan for user approval before any implementation begins.
