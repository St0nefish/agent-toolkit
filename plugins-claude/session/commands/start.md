---
description: "Show available work and pick something to start"
allowed-tools: Bash, Agent, EnterPlanMode
---

Generic entry point. Shows available work, lets the user pick, then explores the codebase and produces an implementation plan.

> **CRITICAL**: When the user picks an issue, you MUST launch Explore agents and enter plan mode. NEVER print "suggested first steps" or ask "ready to start?" — the workflow does not end until you have called EnterPlanMode and presented a plan built from actual code exploration.

### Phase 1 — Show available work

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

### Phase 2 — Act on the user's choice

4. **Act on the user's response:**

   - **Issue number mentioned** (e.g. "#42" or "42") — fetch the full issue with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>`, determine branch type from labels (`bug/fix` → `bug/`, `enhancement/feature/improvement` → `enhancement/`, `docs/chore/refactor/maintenance` → `chore/`, fallback → `feature/`), create the branch (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create <type>/<N>-<slug>`), print the branch name and issue title, then proceed to Phase 3.
   - **Branch name mentioned** — follow the `resume` action (context extraction). Phase 3 does not apply.
   - **Freeform description** — create a `wip/<kebab-slug>` branch: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create wip/<slug>`. No issue is linked. Phase 3 does not apply.

### Phase 3 — Explore the codebase (MANDATORY when an issue is linked)

> You MUST complete this phase when the user selected an issue. Do NOT stop after Phase 2. Do NOT print "suggested first steps".

5. **Launch 2-3 Explore agents in parallel.** Use `Agent` with `subagent_type: Explore`. Each agent gets a different investigation task. Every agent prompt MUST include the full issue title, body text, and labels so it has complete context.

   Pick 2-3 of these investigation tasks based on what the issue describes:

   - **Locate the code:** Find the files, functions, types, or modules mentioned in or implied by the issue. Read them fully. Report: what each does, where the problem or change point is, relevant surrounding code and function signatures.
   - **Find tests and related config:** Search for existing tests covering the affected area, related configuration, CI setup, or documentation. Report: what test coverage exists, what's missing, how the test suite is structured.
   - **Trace the data/call flow:** Follow the call chain or data flow through the area the issue describes. Report: entry points, intermediate steps, dependencies, and edge cases.

   If an agent needs to interact with the issue tracker or repository API, it must use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never call `gh`, `tea`, or other platform CLIs directly.

### Phase 4 — Plan (MANDATORY when an issue is linked)

> You MUST complete this phase. Do NOT stop after Phase 3.

6. **Call `EnterPlanMode`.** Using the agents' findings from Phase 3, produce a concrete implementation plan:
   - List the specific files and line ranges that need changes
   - Describe what each change should do and how (not "fix the bug" — describe the actual code change)
   - Note any tests to add or update
   - Flag risks, edge cases, or open questions

   Present the plan for user approval before any implementation begins.
