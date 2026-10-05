---
description: "Start work from your description — explore the codebase and plan"
allowed-tools: Bash, AskUserQuestion
---

Start work from whatever you describe. This is the **input-driven** door: you say
what to do, it grounds in the current repo state, creates or reuses a branch,
explores the code, and proposes a plan before implementing. To browse and pick from
open issues instead, use `/session:issue`.

> Drive this to a plan. Do NOT end on "suggested first steps" — explore the code and
> propose a concrete plan for approval before implementing.

### Steps

1. **Take the input.** The work comes from your description. If none was given, ask
   what to work on (a single open question) — do **not** enumerate a work board.

2. **Ground in current state** (`git status --short -b`): current branch, default
   branch, uncommitted changes, recent commits. Decide `continuing`:
   - **`continuing` = true** — on a non-default branch that has commits ahead of the
     default branch or uncommitted work. Keep this branch; skip step 4 (name the
     work from the current branch, minus any `worktree-` prefix).
   - **`continuing` = false** — default branch, or a fresh branch with no work: new
     work; create a branch below.

   **Related issues (freeform only).** If the description names no issue, check the
   open issues for ones clearly related to the work
   (`gh issue list --state open --limit 100 --json number,title,body,labels`, or
   `tea issues list --state open --limit 100 --output json` on Gitea). If any exist,
   offer them and link the ones the user picks (treat them as referenced issues in
   step 3); if none or the lookup is unavailable, continue freeform silently.

3. **Validate issues and pick a base branch name:**
   - **References an existing issue** (e.g. "#42") → fetch it (`gh issue view <N>
     --json number,title,body,state,labels,comments` / `tea issues <N> --output
     json`). If the fetch fails, it is not open, or it is a pull request, tell the
     user and drop it or stop. Warn and ask first if it is already claimed (listed in
     `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR).
     Derive the type from labels (compare the last path segment, case-insensitively;
     a `bug` label on any issue wins): `bug`/`fix` → `bug`,
     `enhancement`/`feature`/`improvement` → `enhancement`,
     `docs`/`chore`/`refactor`/`maintenance` → `chore`, else `feature`. Name it
     `<type>-<slug>` (the issue number lives in the PR's closing line, not the
     branch). Keep the body + labels as context. Closing lines: `Fixes #N` for
     `bug` issues, `Closes #N` otherwise.
   - **Freeform** → `wip-<kebab-slug>` (3-5 word slug). No issue linked.

4. **Isolate (new work only).** Default to a worktree for substantial work via the
   repo-local/user-installed `git-worktree` Copilot extension — prefer
   `sf_git_worktree_create` (equivalent direct git flow:
   `git worktree add .github/worktrees/<slug> -b <base-name>`, where `<slug>` is the
   branch name with non-`[A-Za-z0-9._-]` chars replaced by `-`). Then run subsequent
   steps from inside it. Create **in place** (`git switch -c <base-name>`) for trivial
   one-file fixes. Skip this step if already inside a linked worktree.
   - **Collisions.** First check `git worktree list` and
     `git branch --list "<base-name>"`. If it exists, offer to resume it (switch to
     the branch / enter its worktree, then treat as `continuing`) or use a numeric
     suffix (`<base-name>-2`); ask when it could be someone's other work.
   - **Dirty default branch.** Uncommitted edits stay in the main checkout and are
     not carried into the worktree; warn once and ask whether to proceed or work in
     place.
   - **Dependencies.** A fresh worktree is a clean checkout. Symlink or reinstall
     dependency directories only — `node_modules`, `.venv`, `venv`, `vendor` — never
     build output (`target`, `build`, `dist`, `.next`, `.gradle`, `.tox`). Keep a
     symlink out of `git status` by adding `/<dir>` to
     `git rev-parse --git-path info/exclude`.

   **Record issue linkage** (once the branch exists, including when `continuing`;
   skip when no issues are linked): store the closing lines comma-separated, unioning
   with any existing value when `continuing`:

   ```bash
   git config "branch.$(git branch --show-current).session-issues" "Closes #12,Fixes #13"
   ```

   `/session:end` and `/session:orchestrate` read this key. Claude Code's
   session-rename step has no Copilot equivalent and is skipped.

5. **Explore, then plan.** Investigate the relevant code — read the files, trace the
   call/data flow, find existing tests and conventions. For a trivial change (typo,
   one-file fix, issue naming the exact change) read the few files and keep the plan
   to a few lines. Present a concrete plan (files to change and how, testing only
   when behavior changes, risks) and get approval before implementing. **Always end
   the plan with this bullet, verbatim:** "After implementing: STOP and hand off
   (spine Phase 4) - no commit, push, or PR."

6. **Hand off — STOP.** Once the approved work is implemented, do NOT commit, push,
   or open/merge a PR on your own; plan approval authorizes implementation only. Give
   a plain-text wrap-up built from real commands (`git status --short`, commits ahead
   of the default branch): outcome and per-file changes, branch name, work is
   uncommitted (yes/no), test/build status (say so if not run), specific caveats.
   Next steps: `/session:end` or `/git-tools:ship`. With linked issues, list one
   closing line per issue for the PR body (read them from
   `git config branch.$(git branch --show-current).session-issues` if out of
   context). Lightweight is the only flow; mention `/session:orchestrate` only if the
   user asks for a heavier multi-agent flow.
