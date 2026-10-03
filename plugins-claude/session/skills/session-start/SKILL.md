---
disable-model-invocation: true
name: session-start
description: "Start work from your description — explore the codebase and plan"
allowed-tools: Bash, Agent, EnterPlanMode, AskUserQuestion, EnterWorktree, Read, Skill
---

Start work from whatever you describe. This is the **input-driven** door: you say
what to do, it grounds in the current repo state, then runs the shared begin-work
spine (resolve target → isolate → explore → plan). To browse and pick from open
issues instead, use `/session:session-issue`; for a read-only status view, use
`/session:session-summarize`.

> **CRITICAL**: You MUST drive this to a plan. NEVER print "suggested first steps"
> or ask "ready to start?" — the flow does not end until you have explored the code
> and called `EnterPlanMode`. And once the approved work is implemented you **STOP
> and hand back to the user** (spine Phase 4) — never commit, push, open/merge a PR,
> or finalize on your own. Plan approval ≠ permission to publish.

### Phase 0 — Take the input and ground it

1. The work comes from `$ARGUMENTS` (your description). If `$ARGUMENTS` is empty, ask
   the user what they want to work on (a single open-ended prompt) — do **not**
   enumerate a work board; `/session:session-issue` is the issue picker and
   `/session:session-summarize` is the status view.

2. Ground yourself in the current state:

   ```bash
   git status --short -b
   ```

   - **Already on a non-default branch** (with commits ahead or uncommitted work) →
     you are **continuing existing work**. Reuse this branch; tell the spine to skip
     its Isolate phase.
   - **On the default branch** → new work; the spine creates the branch.

3. Identify the target for the spine:
   - **Description references issues** (`#42`, "issue 42", several allowed) → hand
     the issue number(s) to the spine.
   - **Freeform** → hand the description to the spine (it builds `wip-<slug>`).

### Phase 1 — Run the spine

4. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   It owns issue fetching, branch naming, session rename, isolation, exploration
   (including the trivial fast path), planning, and the hand-off. Complete every
   MANDATORY phase — the flow ends only once you have presented a plan.
