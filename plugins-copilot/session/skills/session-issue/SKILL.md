---
disable-model-invocation: true
name: session-issue
description: "Browse open issues, pick one or more, and start work on them"
allowed-tools: Bash, AskUserQuestion
---

The **discovery** door: rank the open issues, pick one or several, then explore the
code and propose a plan. To start from your own description instead, use
`/session:start`.

> Drive this to a plan. Do NOT end on "suggested first steps" — explore the code and
> propose a concrete plan for approval before implementing.

### Steps

1. **Detect the platform once**:

   ```bash
   hostof() { sed -E 's|^[a-z+]+://([^@/]*@)?([^:/]+).*|\2|; t; s|^[^@]*@([^:]+):.*|\1|'; }
   host=$(git remote get-url origin | hostof)
   if [ "$host" = github.com ]; then echo github
   elif tea login list --output json 2>/dev/null | jq -r '.[].url' | hostof | grep -qxF "$host"; then echo gitea
   else echo "unknown host $host: configure a tea login or gh auth" >&2; fi
   ```

   (Mirrors `git-wait platform`: a host equal to the hostname of a configured
   `tea` login is Gitea, `github.com` is GitHub; this is inline because it needs
   no plugin-root variable.)

   If issue numbers were passed as arguments (`#127 #125`, `127 and 125`, `127,125`),
   skip ranking and go straight to step 3 with those numbers.

2. **Fetch and rank ALL open issues** (do not pre-truncate to a top-N). Save the JSON
   to a scratch file (`tmp=$(mktemp)`) and compute the count in the shell:
   - **github:** `gh issue list --state open --limit 200 --json number,title,body,labels,milestone,comments,createdAt > "$tmp"`
   - **gitea:** `tea issues list --state open --limit 200 --output json --fields index,title,body,labels,milestone,comments,created > "$tmp"`

   Then `COUNT=$(jq length "$tmp")`. Use this `COUNT` for the selection below —
   never count by eye. Warn on any displayed issue that already appears in
   `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR.

   Rank by priority (GitHub calls the number `number` and age `createdAt`; Gitea
   calls them `index` and `created`):
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments -> higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   **Select** based on the total number of open issues:
   - **0** — tell the user there are none and suggest `/session:start`. Stop.
   - **1** — state the single `#N — Title` plus a one-line summary, then ask the user
     to confirm before starting (they may want to defer it or do it from a specific
     machine). Only proceed once they confirm.
   - **2–4** — present them via AskUserQuestion (the picker caps at 4 options); several
     may be chosen. Include issue number, title, and labels for each.
   - **5 or more** — too many for the picker. Do NOT use AskUserQuestion. Print the full
     ranked list as plain text — every issue as `#N — Title [labels]` followed by a
     one-line summary of its body — then ask the user to type the number(s) to work on
     (one or several), and wait for their reply.

   Several issues are fine: they share one branch/worktree and one plan.

3. **Fetch and validate every selected issue** in full (github: `gh issue view <N> --json number,title,body,state,labels,comments`; gitea: `tea issues <N> --output json`).
   If a fetch fails, the state is not open, or the number is a pull request, tell
   the user and drop it or stop (ask when unclear). When numbers came from
   arguments, also warn and ask before proceeding if one already appears in
   `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR. Keep
   each body + labels as context for the whole session.

4. **Determine branch type** from issue labels (with several issues, a `bug` label on
   any of them wins; otherwise use the first issue's labels):
   - `bug`, `fix` -> `bug`
   - `enhancement`, `feature`, `improvement` -> `enhancement`
   - `docs`, `chore`, `refactor`, `maintenance` -> `chore`
   - No matching label -> `feature`

5. **Isolate.** First ground `continuing` with `git status --short -b`: on a
   non-default branch with commits ahead or uncommitted work, `continuing` is
   **true** — keep the branch, skip the rest of this step's creation, and just record
   linkage below. Also skip creation if already inside a linked worktree, and if
   `<type>-<slug>` already exists (check `git worktree list` and `git branch --list`)
   offer to resume it or use a numeric suffix. Otherwise, default to a worktree for substantial work via the
   `git-worktree` Copilot extension — prefer `sf_git_worktree_create`
   (equivalent direct flow: `git worktree add .github/worktrees/<slug> -b <type>-<slug>`)
   — then run subsequent steps from inside it. Create **in place**
   (`git switch -c <type>-<slug>`) for trivial one-file fixes. `<slug>` is a
   kebab-case 3-5 word slug from the (first) issue title, or the common theme when
   several are bundled. Issue numbers live in the PR's closing lines, not the branch name.
   In a fresh worktree, symlink or reinstall dependency directories only
   (`node_modules`, `.venv`, `venv`, `vendor`), never build output.

   **Record issue linkage** once the branch exists (including when `continuing`,
   unioning with any existing value): one closing line per issue, `Fixes #N` for
   `bug` issues, `Closes #N` otherwise, comma-separated:

   ```bash
   git config "branch.$(git branch --show-current).session-issues" "Closes #12,Fixes #13"
   ```

6. **Explore, then plan.** Investigate the relevant code — read the files, trace the
   call/data flow, find existing tests and conventions. Then present a concrete plan
   (files to change and how, testing, risks) and get approval before implementing.
   End the plan with this bullet, verbatim: "After implementing: STOP and hand off
   (spine Phase 4) - no commit, push, or PR." Once the approved work is implemented, STOP and hand back: do not commit, push, or
   open/merge a PR on your own — plan approval authorizes implementation only. Give a
   plain-text wrap-up from real commands (`git status --short`, commits ahead of the
   default branch): outcome, branch, uncommitted yes/no, test status, caveats. List
   one closing line per issue (`Fixes #N` for bugs, `Closes #N` otherwise) for the
   PR body, reading them from the `session-issues` git config if out of context. Next steps: `/session:end` or `/git-tools:ship`. Lightweight is the only
   flow; mention `/session:orchestrate` only if the user asks for a heavier
   multi-agent flow.
