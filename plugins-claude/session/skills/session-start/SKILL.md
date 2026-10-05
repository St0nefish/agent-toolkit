---
disable-model-invocation: true
name: session-start
description: "Start work from your description — explore the codebase and plan"
allowed-tools: Bash, Agent, EnterPlanMode, AskUserQuestion, EnterWorktree, Read, Skill
---

Start work from whatever you describe. This is the **input-driven** door: you say
what to do, it grounds in the current repo state, checks for open issues related
to the work, then runs the shared begin-work
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
     `continuing` is **true**. Reuse this branch; the spine skips Isolate and names
     the session from the current branch.
   - **Otherwise** (default branch, or a fresh branch with no work) → `continuing`
     is **false**; the spine creates the branch.

   Pass `continuing` to the spine.

3. Identify the target for the spine:
   - **Description references issues** (`#42`, "issue 42", several allowed) → hand
     the issue number(s) to the spine.
   - **Freeform** → run the related-issue lookup below, then hand the spine either
     the issues the user linked or, if none, the description (it builds `wip-<slug>`).

4. **Related-issue lookup** (freeform only — skip when step 3 found `#N` references).
   Open issues may already describe this work; find them so the PR can close them.

   a. Detect the platform once (the spine reuses it — do not detect again):

      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
      ```

   If detection fails (no remote or no CLI), skip the lookup silently and
   continue as freeform.

   b. Launch one `Agent` (`subagent_type: general-purpose`, `model: haiku`) with the
   description and the platform. Tell it to fetch open issues —
   **github:** `gh issue list --state open --limit 100 --json number,title,body,labels`;
   **gitea:** `tea issues list --state open --limit 100 --output json --fields index,title,body,labels` —
   and return up to 5 issues that are **clearly related** to the description
   (favor precision; omit weak matches), each as `#N — Title [labels]` plus a
   one-line reason, or just `NONE`.

   c. **`NONE`** → continue as freeform without comment. **One or more** →
   `AskUserQuestion` with `multiSelect: true` (max 4 options, label
   `#N — Title`, description = labels + reason). Selected issues become the
   spine's issue target; none selected → freeform.

### Phase 1 — Run the spine

5. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   It owns issue fetching, branch naming, isolation, issue-linkage recording, session
   rename, exploration (including the trivial fast path), planning, and the hand-off. Complete every
   MANDATORY phase — the flow ends only once you have presented a plan.
