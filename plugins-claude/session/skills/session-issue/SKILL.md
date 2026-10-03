---
disable-model-invocation: true
name: session-issue
description: "Browse open issues, pick one or more, and start work on them"
allowed-tools: Agent, Bash, AskUserQuestion, EnterPlanMode, EnterWorktree, Read, Skill
---

The **discovery** door: rank the open issues, pick one or several, then run the
shared begin-work spine (resolve target → isolate → explore → plan). To start from
your own description instead, use `/session:session-start`.

> **CRITICAL**: You MUST drive this to a plan. NEVER print "suggested first steps"
> or ask "ready to start?" — the flow does not end until you have explored the code
> and called `EnterPlanMode`. And once the approved work is implemented you **STOP
> and hand back to the user** (spine Phase 4) — never commit, push, open/merge a PR,
> or finalize on your own. Plan approval ≠ permission to publish.

### Phase 1 — Pick issues

1. **Detect the platform once** (the spine reuses it — do not detect again):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
   ```

2. **Issue numbers in `$ARGUMENTS`** (`#127 #125 #115`, `127 and 125`, `127,125`):
   skip the ranked list and go straight to Phase 2 with those numbers.

3. **Otherwise fetch and rank ALL open issues using a subagent.** Launch an `Agent`
   (`subagent_type: general-purpose`) with this prompt, substituting the detected
   `<platform>`:

   > Fetch open issues, rank them, and return ALL of them (not a top-N subset).
   > The platform is `<platform>` — do not re-detect it. Run the matching command:
   >
   > - **github:**
   >
   >   ```bash
   >   gh issue list --state open --limit 50 \
   >     --json number,title,body,labels,milestone,comments,createdAt
   >   ```
   >
   > - **gitea:**
   >
   >   ```bash
   >   tea issues list --state open --limit 50 --output json \
   >     --fields index,title,body,labels,milestone,comments,created
   >   ```
   >
   > (GitHub calls the issue number `number` and the age field `createdAt`;
   > Gitea calls them `index` and `created` — treat them the same either way.)
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

4. **Pick** based on the total `COUNT` of open issues:
   - **0** — tell the user there are no open issues and suggest
     `/session:session-start` to begin from your own description. Stop here.
   - **1** — state the single issue (`#N — Title`) plus its one-line summary, then
     **ask the user to confirm** before starting. Only enter Phase 2 once they confirm.
   - **2–4** — present them via `AskUserQuestion` with `multiSelect: true` (the
     picker caps at 4 options, so the whole set fits). Each option label is
     `#N — Title`; the description carries the labels and the one-line summary.
   - **5 or more** — too many for the picker. Do NOT use `AskUserQuestion`. Print the
     full ranked list as plain text — every issue, each as its `#N — Title [labels]`
     line followed by its one-line summary — then ask the user to **type the
     number(s)** they want (one or several, e.g. `127`, `127 125`, `#127 and #125`).
     Wait for their text reply. (Do not pre-truncate to a "top N" — let the user
     scan the whole list.)

   Several issues are fine: they share one branch/worktree and one plan.

### Phase 2 — Run the spine

5. **Read the shared begin-work spine and execute it** (use the Read tool):

   ```text
   ${CLAUDE_PLUGIN_ROOT}/reference/spine.md
   ```

   Hand it the chosen issue number(s) and the detected platform. The spine fetches
   every issue, builds the base branch name, renames the session, isolates, explores
   (including the trivial fast path), plans one plan covering **all** chosen issues,
   and hands off with one closing line per issue. Complete every MANDATORY phase —
   the flow ends only once you have presented a plan.
