---
description: "Show available work and pick something to start"
allowed-tools: Bash, Agent, EnterPlanMode
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

5. **Confirm briefly.** Print the branch name and linked issue title (if any). Do NOT print suggested steps or ask "want me to start?" — proceed immediately to step 6.

6. **Explore and plan** — mandatory when an issue is linked, skip for freeform descriptions or branch resumes.

   Immediately launch 2-3 Agents **in parallel** (subagent_type: Explore) to investigate the issue. Do not skip this step. Do not summarize the issue and ask the user what to do — the agents must run now.

   Design each agent's prompt to answer a specific question about the codebase. Include the full issue title, body, and labels in every agent prompt. Tell each agent to read the actual source files and report concrete findings (file paths, line numbers, code snippets, function signatures).

   Agent prompts to choose from (pick 2-3 based on the issue):

   - **Locate the code:** Find the files, functions, types, or modules mentioned in or implied by the issue. Read them fully. Report: what each does, where the problem or change point is, relevant surrounding code and function signatures.
   - **Find tests and related config:** Search for existing tests covering the affected area, related configuration, CI setup, or documentation. Report: what test coverage exists, what's missing, how the test suite is structured.
   - **Trace the data/call flow:** Follow the call chain or data flow through the area the issue describes. Report: entry points, intermediate steps, dependencies, and edge cases.

   If an agent needs to interact with the issue tracker or repository API, it must use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never call `gh`, `tea`, or other platform CLIs directly.

7. **Enter plan mode.** After all agents return, call `EnterPlanMode`. Using the agents' findings, produce a concrete implementation plan:
   - List the specific files and line ranges that need changes
   - Describe what each change should do and how (not "fix the bug" — describe the actual code change)
   - Note any tests to add or update
   - Flag risks, edge cases, or open questions

   Present the plan for user approval before any implementation begins.
