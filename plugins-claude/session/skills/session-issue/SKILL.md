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

1. **Fetch and rank ALL open issues using a subagent.** Launch an `Agent`
   (`subagent_type: general-purpose`) with this prompt:

   > Fetch open issues, rank them, and return ALL of them (not a top-N subset).
   >
   > Run this command:
   >
   > ```bash
   > bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue list --limit 50 --state open
   > ```
   >
   > From the returned JSON array, rank by priority using these criteria:
   > - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   > - Issues with a milestone set rank higher than those without
   > - More comments → higher priority (community signal)
   > - Older issues rank higher than newer (age as proxy for neglect)
   >
   > Return EVERY open issue, highest priority first. Start your reply with a single
   > line `COUNT: <n>` giving the total number of open issues. Then, for each issue,
   > emit a two-line block:
   >
   > ```text
   > #N — Title [label1, label2]
   >     <one-sentence summary of the issue body, ≤25 words>
   > ```
   >
   > Derive the summary from each issue's `body` field in the JSON (it is already
   > included — do not fetch issues individually). If a body is empty, write
   > `(no description)`.

2. **Pick the issue** based on the total `COUNT` of open issues:
   - **0** — tell the user there are no open issues and suggest
     `/session:session-start` to begin from your own description. Stop here.
   - **1** — state the single issue (`#N — Title`) plus its one-line summary, then
     **ask the user to confirm** before starting (e.g. "This is the only open issue —
     work on it now?"). Do not auto-proceed: the user may want to defer it, do it from
     a specific machine/node, or start from their own description instead. Only enter
     Phase 2 once they confirm.
   - **2–4** — present them via `AskUserQuestion` (the picker caps at 4 options, so the
     whole set fits). Each option label is `#N — Title`; the description carries the
     labels and the one-line summary.
   - **5 or more** — too many for the picker. Do NOT use `AskUserQuestion`. Print the
     full ranked list as plain text — every issue, each as its `#N — Title [labels]`
     line followed by its one-line summary — then ask the user to **type the number** of
     the issue they want to work on. Wait for their text reply and use that number.
     (Forcing dozens of issues through a picker, or pre-truncating to a "top N", buries
     real choices behind the agent's guess at what "top" means — let the user scan the
     whole list and pick.)

3. **Fetch the full issue** (save the body and labels — the spine needs them as
   context):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <N>
   ```

### Phase 2 — Base branch name

4. **Determine the branch type** from the issue labels:
   - `bug`, `fix` → `bug`
   - `enhancement`, `feature`, `improvement` → `enhancement`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore`
   - No matching label → `feature`

5. **Build the base name** as `<type>-<slug>`, where `<slug>` is a kebab-case
   3-5 word slug from the issue title. Example: issue #42 "Fix login crash on empty
   password" → `bug-fix-login-crash`. The branch name does not encode the issue
   number — the linkage lives in the PR's `Closes #N`, which is what auto-closes
   the issue on merge.

### Phase 3 — Run the spine

6. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   Hand it the issue body + labels as context and the base branch name from Phase 2.
   The spine drives Isolate (worktree) → Escalate-to-orchestrate? → Explore (parallel
   research agents) → Plan (`EnterPlanMode`) → Hand-off. Complete every MANDATORY
   phase — the flow ends only once you have presented a plan.
