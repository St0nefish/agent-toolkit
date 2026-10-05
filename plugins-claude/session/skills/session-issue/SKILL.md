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

   If detection fails (no remote, no CLI, or no supported platform), say there is no
   issue tracker here, suggest `/session:session-start`, and stop.

2. **Issue numbers in `$ARGUMENTS`** (`#127 #125 #115`, `127 and 125`, `127,125`):
   skip the ranked list. Validate each number first: fetch it (github:
   `gh issue view <N> --json number,title,state`; gitea: `tea issues <N> --output json`)
   and, if the fetch fails, the state is not open, or it is a pull request, tell the
   user and drop it or stop (ask when unclear). If any remain, go to Phase 2.
   Also warn and ask before proceeding when a number already appears in
   `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR.

3. **Otherwise fetch and rank ALL open issues.** Fetch the JSON in the shell (not in
   a subagent), saving it to a scratch file (`tmp=$(mktemp)`), and compute the count
   there:

   - **github:**

     ```bash
     gh issue list --state open --limit 200 \
       --json number,title,body,labels,milestone,comments,createdAt > "$tmp"
     ```

   - **gitea:**

     ```bash
     tea issues list --state open --limit 200 --output json \
       --fields index,title,body,labels,milestone,comments,created > "$tmp"
     ```

   Then `COUNT=$(jq length "$tmp")`. Use this `COUNT` for the pick step — never ask
   the model to count. If `COUNT` is 0 or 1, skip the ranking agent (the pick step
   needs only that issue's title and a one-line summary you write yourself).
   Otherwise launch an `Agent` (`subagent_type: general-purpose`, `model: haiku`)
   with the scratch file path and this prompt:

   > Read the JSON array of open issues in `<path>` (GitHub calls the issue number
   > `number` and the age field `createdAt`; Gitea calls them `index` and `created` —
   > treat them the same). Rank ALL issues by priority, highest first:
>
> - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
> - Issues with a milestone set rank higher than those without
> - More comments → higher priority (community signal)
> - Older issues rank higher than newer (age as proxy for neglect)
   >
   > Return EVERY issue, as a two-line block each:
   >
   > ```text
   > #N — Title [label1, label2]
   >     <one-sentence summary of the issue body, ≤25 words>
   > ```
   >
   > Summarise only what is returned; do not quote bodies in full. If a body is
   > empty, write `(no description)`. Do not fetch issues individually.

   Warn on any displayed issue that already appears in
   `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR.

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

   Ground `continuing` first: run `git status --short -b`; if on a non-default branch
   with commits ahead or uncommitted work, `continuing` is **true** (the spine skips
   Isolate and reuses the branch), otherwise **false**.

   Hand the spine the chosen issue number(s), the detected platform, and `continuing`.
   The spine fetches every issue, builds the base branch name, isolates, records issue
   linkage, renames the session, explores (including the trivial fast path), plans one
   plan covering **all** chosen issues, and hands off with one closing line per issue. Complete every MANDATORY phase —
   the flow ends only once you have presented a plan.
