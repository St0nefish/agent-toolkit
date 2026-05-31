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

2. **Rank.** From the returned JSON array, rank ALL issues by priority (do not
   pre-truncate to a top-N):
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments -> higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   **Select** based on the total number of open issues:
   - **0** — tell the user there are none and suggest `/session:session-start`. Stop.
   - **1** — state the single `#N — Title` plus a one-line summary, then ask the user
     to confirm before starting (they may want to defer it or do it from a specific
     machine). Only proceed once they confirm.
   - **2–4** — present them via AskUserQuestion (the picker caps at 4 options). Include
     issue number, title, and labels for each.
   - **5 or more** — too many for the picker. Do NOT use AskUserQuestion. Print the full
     ranked list as plain text — every issue as `#N — Title [labels]` followed by a
     one-line summary of its body — then ask the user to type the number of the issue to
     work on, and wait for their reply.

3. **Fetch the full issue** details and recent discussion for the selection. Keep the
   body + labels as context.

4. **Determine branch type** from issue labels:
   - `bug`, `fix` -> `bug`
   - `enhancement`, `feature`, `improvement` -> `enhancement`
   - `docs`, `chore`, `refactor`, `maintenance` -> `chore`
   - No matching label -> `feature`

5. **Isolate.** Default to a worktree for substantial work via the `git-worktree`
   plugin — `git worktree add .github/worktrees/<slug> -b <type>-<slug>` — then
   run subsequent steps from inside it. Create **in place**
   (`git switch -c <type>-<slug>`) for trivial one-file fixes. `<slug>` is a
   kebab-case 3-5 word slug from the issue title. The issue number lives in the PR's
   `Closes #N`, not the branch name.

6. **Maybe offer orchestration.** Lightweight is the default — do NOT surface this
   on every run. First judge scope yourself; treat the issue as complex only when
   **two or more** signals hold: multiple files/subsystems, real design ambiguity,
   correctness-critical path, a long/multi-part spec (≳300-word body, several
   acceptance criteria/checkboxes), or keywords like `refactor`, `redesign`,
   `migration`, `architecture`, `system`. For simple or moderate issues, say nothing
   about orchestrate and continue. Only when genuinely complex, offer
   `/session:session-orchestrate` once. If the user escalates, hand off and stop.

7. **Explore, then plan.** Investigate the relevant code — read the files, trace the
   call/data flow, find existing tests and conventions. Then present a concrete plan
   (files to change and how, testing, risks) and get approval before implementing.
   When done, give a plain-text wrap-up (summary, current state, caveats) and let the
   user decide what's next — do not auto-commit or force a menu. Include `Closes #N`
   (or `Fixes #N` for bugs) when you later commit or open a PR so the issue
   auto-closes on merge.
