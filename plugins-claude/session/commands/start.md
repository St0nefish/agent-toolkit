---
description: "Show available work and pick something to start"
allowed-tools: Bash, Agent
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
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue list --limit 20 --state open
   ```

   **Active branches** (in-progress work) — branches not yet merged to the default branch:

   ```bash
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo default-branch)
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

6. **Explore and plan** (when an issue is linked). Launch 2-3 Agents **in parallel** (subagent_type: Explore) to investigate the issue. Design each agent's prompt based on what the issue describes — for example:

   - **Agent A — locate the code:** search for files, functions, types, or modules mentioned in or implied by the issue. Read them and report what each does, where the problem likely lives, and relevant surrounding code.
   - **Agent B — find related tests/config:** search for existing tests, related config, CI setup, or documentation that covers the affected area. Report what exists and what's missing.
   - **Agent C — trace the flow** (if relevant): follow the call chain or data flow through the area the issue describes. Report entry points, dependencies, and edge cases.

   Tailor the agents to the specific issue — not every issue needs all three. Each agent prompt must include the full issue title, body, and labels.

   Once all agents return, synthesize their findings into a concrete implementation plan:
   - List the specific files and line ranges that need changes
   - Describe what each change should do (not just "fix the bug" — say *how*)
   - Note any tests to add or update
   - Flag risks, edge cases, or questions that need the user's input

   Present the plan to the user as the starting point for work.

   For **freeform descriptions** (no issue linked) or **branch resumes**, skip the exploration — the user already has context or the `/session:catchup` skill will handle it.
