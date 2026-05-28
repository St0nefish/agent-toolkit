---
description: "Browse open issues, pick one, and start work on it"
allowed-tools: Bash, AskUserQuestion
---

The **discovery** door: rank the open issues, pick one, then explore the code and
propose a plan. To start from your own description instead, use
`/session:session-start`.

> Drive this to a plan. Do NOT end on "suggested first steps" — explore the code and
> propose a concrete plan for approval before implementing.

### Steps

1. **Fetch open issues** with native host tooling:
   - on GitHub repos, prefer
     `gh issue list --limit 20 --state open --json number,title,labels,milestone,comments,createdAt`
   - on other hosts, use the equivalent host-native issue command if available

2. **Rank and select.** From the returned JSON array, pick the top 3 by priority:
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments -> higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   Display the top 3 as choices via AskUserQuestion. Include issue number, title, and
   labels for each.

3. **Fetch the full issue** details and recent discussion for the selection. Keep the
   body + labels as context.

4. **Determine branch type** from issue labels:
   - `bug`, `fix` -> `bug/`
   - `enhancement`, `feature`, `improvement` -> `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` -> `chore/`
   - No matching label -> `feature/`

5. **Isolate.** Default to a worktree for substantial work via the `git-worktree`
   plugin — `git worktree add .github/worktrees/<slug> -b <type>/<N>-<slug>` — then
   run subsequent steps from inside it. Create **in place**
   (`git switch -c <type>/<N>-<slug>`) for trivial one-file fixes. `<slug>` is a
   kebab-case 3-5 word slug from the issue title.

6. **Offer orchestration.** If the issue suggests non-trivial scope (long body,
   multiple acceptance criteria, keywords like `refactor`, `redesign`, `migration`,
   `architecture`, `feature`), offer `/session:session-orchestrate`. Skip for clearly
   small issues. If the user escalates, hand off and stop.

7. **Explore, then plan.** Investigate the relevant code — read the files, trace the
   call/data flow, find existing tests and conventions. Then present a concrete plan
   (files to change and how, testing, risks) and get approval before implementing.
   When done, give a plain-text wrap-up (summary, current state, caveats) and let the
   user decide what's next — do not auto-commit or force a menu. Include `Closes #N`
   (or `Fixes #N` for bugs) when you later commit or open a PR so the issue
   auto-closes on merge.
