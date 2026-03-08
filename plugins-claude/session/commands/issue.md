---
description: "Select an open issue and begin work on it"
allowed-tools: Agent, Bash, AskUserQuestion, EnterPlanMode
---

Select an open issue, create a branch, explore the codebase, and produce an implementation plan.

> **CRITICAL**: After the branch is created you MUST launch Explore agents and enter plan mode. NEVER print "suggested first steps" or ask "ready to start?" — the workflow does not end until you have called EnterPlanMode and presented a plan built from actual code exploration.

### Phase 1 — Pick an issue

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

3. Fetch the full issue (save the body and labels — you will need them in Phase 2):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>
   ```

### Phase 2 — Create the branch

4. **Determine branch type** from issue labels:
   - `bug`, `fix` → `bug/`
   - `enhancement`, `feature`, `improvement` → `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore/`
   - No matching label → `feature/`

5. **Create the branch.** Generate a kebab-case slug (3-5 words) from the issue title:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create <type>/<N>-<slug>
   ```

   Example: issue #42 "Fix login crash on empty password" → `bug/42-fix-login-crash`

6. **Print exactly two lines** — the branch name and the issue title. Nothing else. Then immediately proceed to Phase 3.

### Phase 3 — Explore the codebase (MANDATORY)

> You MUST complete this phase. Do NOT stop after Phase 2.

7. **Launch 2-3 Explore agents in parallel.** Use `Agent` with `subagent_type: Explore`. Each agent gets a different investigation task. Every agent prompt MUST include the full issue title, body text, and labels so it has complete context.

   Pick 2-3 of these investigation tasks based on what the issue describes:

   - **Locate the code:** Find the files, functions, types, or modules mentioned in or implied by the issue. Read them fully. Report: what each does, where the problem or change point is, relevant surrounding code and function signatures.
   - **Find tests and related config:** Search for existing tests covering the affected area, related configuration, CI setup, or documentation. Report: what test coverage exists, what's missing, how the test suite is structured.
   - **Trace the data/call flow:** Follow the call chain or data flow through the area the issue describes. Report: entry points, intermediate steps, dependencies, and edge cases.

   If an agent needs to interact with the issue tracker or repository API, it must use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never call `gh`, `tea`, or other platform CLIs directly.

### Phase 4 — Plan (MANDATORY)

> You MUST complete this phase. Do NOT stop after Phase 3.

8. **Call `EnterPlanMode`.** Using the agents' findings from Phase 3, produce a concrete implementation plan. The plan MUST include all of the following sections:

   **Changes:**
   - List the specific files and line ranges that need changes
   - Describe what each change should do and how (not "fix the bug" — describe the actual code change)

   **Testing (REQUIRED):**
   - Identify what tests to add or update — unit tests, integration tests, or script-level tests as appropriate for the codebase
   - If the project has an existing test framework/runner, use it; if not, add lightweight validation (e.g. a test script) proportional to the change
   - Only skip tests if the change is purely cosmetic (comments, docs, formatting) — otherwise tests are mandatory

   **Risks & open questions:**
   - Flag edge cases, breaking changes, or unknowns

   **Post-implementation steps:**
   - Summarize all changes (overall summary + per-file change summary)
   - Present the user with options: (a) commit, push, and create PR, or (b) provide input to make adjustments
   - When creating a commit or PR for an issue, include `Closes #N` (or `Fixes #N` for bugs) in the commit message or PR body so the issue is auto-closed on merge
   - Do NOT auto-commit — always ask first

   Present the plan for user approval before any implementation begins.
