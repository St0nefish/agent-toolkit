---
disable-model-invocation: true
name: session-start
description: "Start work from your description — explore the codebase and plan"
allowed-tools: Bash, Agent, EnterPlanMode, AskUserQuestion, EnterWorktree, Read, Skill
---

Start work from whatever you describe. This is the **input-driven** door: you say
what to do, it grounds in the current repo state, creates or reuses a branch, then
runs the shared begin-work spine (explore → plan). To browse and pick from open
issues instead, use `/session:session-issue`; for a read-only status view, use
`/session:session-summarize`.

> **CRITICAL**: You MUST drive this to a plan. NEVER print "suggested first steps"
> or ask "ready to start?" — the flow does not end until you have explored the code
> with research agents and called `EnterPlanMode`. And once the approved work is
> implemented you **STOP and hand back to the user** (spine Phase 5) — never commit,
> push, open/merge a PR, or finalize on your own. Plan approval ≠ permission to publish.

### Phase 0 — Take the input and ground it

1. The work comes from `$ARGUMENTS` (your description). If `$ARGUMENTS` is empty, ask
   the user what they want to work on (a single open-ended `AskUserQuestion` or plain
   prompt) — do **not** enumerate a work board; `/session:session-issue` is the issue
   picker and `/session:session-summarize` is the status view.

2. Ground yourself in the current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   Read the output:
   - **Already on a feature branch** (not the default, with prior commits or
     uncommitted work) → you are **continuing existing work**. Reuse this branch; do
     NOT create a new one. Skip Phase 1 and tell the spine to skip its Isolate phase.
   - **On the default branch** → this is new work; create a branch in Phase 1.

### Phase 1 — Identify the target & base branch (new work only)

3. Interpret the description to pick a base branch name:
   - **References an existing issue** (e.g. "#42", "issue 42") → fetch it and link it:

     ```bash
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>
     ```

     Derive the branch type from labels (`bug`/`fix` → `bug`,
     `enhancement`/`feature`/`improvement` → `enhancement`,
     `docs`/`chore`/`refactor`/`maintenance` → `chore`, else `feature`). Base name:
     `<type>-<slug>` (the issue number lives in the PR's `Closes #N`, not the branch).
     Keep the issue body + labels as context.
   - **Freeform** → base name `wip-<kebab-slug>` (3-5 word slug from the description).
     No issue linked; the description is the context.

4. **Rename this session** — invoke the built-in rename via the `Skill` tool
   (`skill: "rename"`, no args). Call it regardless of whether this is new work
   or a continuation — the description from Phase 0 is in context and the rename
   auto-generates a short descriptive name from it.

### Phase 2 — Run the spine

5. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   Hand it the context you gathered (the freeform description and/or the issue
   body + labels) and the base branch name from Phase 1. The spine drives Isolate
   (worktree) → Escalate-to-orchestrate? → Explore (parallel research agents) →
   Plan (`EnterPlanMode`) → Hand-off. If Phase 0 determined you are continuing
   an existing branch, tell the spine to skip its Isolate phase. Complete every
   MANDATORY phase — the flow ends only once you have presented a plan.
