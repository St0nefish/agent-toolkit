---
disable-model-invocation: true
name: session-issue
description: "Browse open issues, pick one, and start work on it"
allowed-tools: Agent, Bash, AskUserQuestion, EnterPlanMode, EnterWorktree, Read
---

The **discovery** door: rank the open issues, pick one, then run the shared
begin-work spine (explore → plan). To start from your own description instead, use
`/session:session-start`.

> **CRITICAL**: You MUST drive this to a plan. NEVER print "suggested first steps"
> or ask "ready to start?" — the flow does not end until you have explored the code
> with research agents and called `EnterPlanMode`.

### Phase 1 — Pick an issue

1. **Fetch and rank issues using a subagent.** Launch an `Agent`
   (`subagent_type: general-purpose`) with this prompt:

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
   > Return ONLY the top 3 issues. For each, include: number, title, and labels
   > (comma-separated). Format each as a single line:
   > `#N — Title [label1, label2]`

2. **Pick the issue** based on how many open issues came back:
   - **None** — tell the user there are no open issues and suggest
     `/session:session-start` to begin from your own description. Stop here.
   - **Exactly one** — skip the menu (`AskUserQuestion` needs ≥2 options). State the
     single issue (`#N — Title`) and proceed with it directly into Phase 2.
   - **Two or more** — present the top 3 via `AskUserQuestion`. Each option label is
     `#N — Title`; the description lists the labels.

3. **Fetch the full issue** (save the body and labels — the spine needs them as
   context):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>
   ```

### Phase 2 — Base branch name

4. **Determine the branch type** from the issue labels:
   - `bug`, `fix` → `bug/`
   - `enhancement`, `feature`, `improvement` → `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore/`
   - No matching label → `feature/`

5. **Build the base name** as `<type>/<N>-<slug>`, where `<slug>` is a kebab-case
   3-5 word slug from the issue title. Example: issue #42 "Fix login crash on empty
   password" → `bug/42-fix-login-crash`.

### Phase 3 — Run the spine

6. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   Hand it the issue body + labels as context and the base branch name from Phase 2.
   The spine drives Isolate (worktree) → Escalate-to-orchestrate? → Explore (parallel
   research agents) → Plan (`EnterPlanMode`) → Hand-off. Complete every MANDATORY
   phase — the flow ends only once you have presented a plan.
