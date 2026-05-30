---
description: "Start work from your description — explore the codebase and plan"
allowed-tools: Bash, AskUserQuestion
---

Start work from whatever you describe. This is the **input-driven** door: you say
what to do, it grounds in the current repo state, creates or reuses a branch,
explores the code, and proposes a plan before implementing. To browse and pick from
open issues instead, use `/session:session-issue`.

> Drive this to a plan. Do NOT end on "suggested first steps" — explore the code and
> propose a concrete plan for approval before implementing.

### Steps

1. **Take the input.** The work comes from your description. If none was given, ask
   what to work on (a single open question) — do **not** enumerate a work board.

2. **Ground in current state:** current branch, default branch, uncommitted changes,
   recent commits.
   - **Already on a feature branch** (with prior commits or uncommitted work) →
     continue it; do NOT create a new branch (skip steps 3-4).
   - **On the default branch** → new work; create a branch below.

3. **Pick a base branch name:**
   - **References an existing issue** (e.g. "#42") → fetch it, derive the type from
     labels (`bug`/`fix` → `bug`, `enhancement`/`feature`/`improvement` →
     `enhancement`, `docs`/`chore`/`refactor`/`maintenance` → `chore`, else
     `feature`), name `<type>-<slug>` (the issue number lives in the PR's `Closes #N`,
     not the branch). Keep the issue body + labels as context.
   - **Freeform** → `wip-<kebab-slug>` (3-5 word slug). No issue linked.

4. **Isolate (new work only).** Default to a worktree for substantial work via the
   `git-worktree` plugin — `git worktree add .github/worktrees/<slug> -b <base-name>`
   (slug = branch name with non-`[A-Za-z0-9._-]` chars replaced by `-`), then run
   subsequent steps from inside it. Create **in place** (`git switch -c <base-name>`)
   for trivial one-file fixes. A fresh worktree is a clean checkout — reinstall or
   symlink heavy gitignored deps (`node_modules`, `.venv`) if needed.

5. **Maybe offer orchestration.** Lightweight is the default — do NOT surface this
   on every run. First judge scope yourself; treat the work as complex only when
   **two or more** signals hold: multiple files/subsystems, real design ambiguity,
   correctness-critical path, a long/multi-part spec (≳300-word body, several
   acceptance criteria), or keywords like `refactor`, `redesign`, `migration`,
   `architecture`, `system`. For simple or moderate work, say nothing about
   orchestrate and continue. Only when genuinely complex, offer
   `/session:session-orchestrate` (multi-agent dispatch, model tiering, automated
   review) once. If the user escalates, hand off and stop.

6. **Explore, then plan.** Investigate the relevant code — read the files, trace the
   call/data flow, find existing tests and conventions. Then present a concrete plan
   (files to change and how, testing, risks) and get approval before implementing.
   When done, give a plain-text wrap-up (summary, current state, caveats) and let the
   user decide what's next — do not auto-commit or force a menu. If an issue is
   linked, include `Closes #N` (or `Fixes #N`) when you later commit or open a PR.
