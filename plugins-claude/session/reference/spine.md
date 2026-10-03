# Begin-work spine

The shared playbook for the lightweight session entrypoints (`session-start` and
`session-issue`). Both doors differ only in **how the work is chosen** — once the
work is identified, they run these phases identically: resolve target → isolate →
explore → plan → hand-off.

**Lightweight is the only flow here.** Do not ask "lightweight vs orchestrate", and
do not ask about worktree vs in-place, dependency symlinks, latency, or scope —
decide silently using the defaults below. Ask only when something is genuinely
ambiguous about **what to build**. If the user asks for a heavier multi-agent flow,
mention once that `/session:session-orchestrate` exists and invoke it; never raise
it unprompted.

> **CRITICAL**: You MUST drive this through to a plan. After the branch exists you
> explore and enter plan mode. NEVER print "suggested first steps" or ask "ready to
> start?" — the flow does not end until you have called `EnterPlanMode` with a plan
> built from real code exploration.
>
> **EQUALLY CRITICAL — the other end of the flow**: after the approved work is
> implemented you **STOP** (Phase 4) and wait for the user. You never commit, push,
> open/merge a PR, or finalize on your own. Plan approval ≠ permission to publish.

## Inputs (supplied by the calling door)

- One of: **issue number(s)** (from `session-issue`, or `#N` references in a
  `session-start` description) or a **freeform description**.
- Whether the door already knows the hosting `platform` (reuse it; never detect
  twice) and whether you are **continuing an existing branch**.

If you reach this spine with neither issues nor a description, stop and return to
the calling door — it owns target selection.

## Phase 0 — Resolve target

Run this once, for both doors.

1. **Fetch issues** (skip for freeform work). Detect the platform once unless the
   door already did, then fetch **every** referenced issue:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
   ```

   - **github:** `gh issue view <N> --json number,title,body,state,labels,comments`
   - **gitea:** `tea issues <N> --output json`

   For anything beyond issue viewing (PR create, CI runs, state values), use the
   command map in the `git-tools:git-wait` skill rather than guessing flags.
   Keep each issue's title, body, and labels as context for the whole session.

2. **Pick the branch type** from labels. With several issues, a `bug` label on any
   of them wins; otherwise use the first issue's labels:
   - `bug`, `fix` → `bug`
   - `enhancement`, `feature`, `improvement` → `enhancement`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore`
   - no matching label → `feature`

3. **Build the base name.** Issue-linked: `<type>-<slug>`; freeform:
   `wip-<slug>`. The slug is a kebab-case 3-5 word summary (of the first issue's
   title, or the common theme when several issues are bundled; of the description
   for freeform). The branch never encodes issue numbers — linkage is the closing
   lines in the PR body.

   Actual branch names: created in place, the branch is `<base-name>`; created via
   `EnterWorktree` (Phase 1), it is `worktree-<base-name>`.

4. **Rename the session** (also when continuing an existing branch):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/rename-session "<base-name>"
   ```

5. **Closing lines.** Remember one line per issue for the hand-off: `Fixes #N` for
   `bug` issues, `Closes #N` otherwise.

## Phase 1 — Isolate

**Skip this phase entirely** when resuming an existing branch, or when already
inside a worktree (`git rev-parse --git-common-dir` resolves outside
`git rev-parse --show-toplevel`) — proceed on the current checkout.

Decide silently:

- **Repo's `CLAUDE.md` says to work directly on the default branch / master** (as
  `homelab-admin` does): do not create a branch or worktree; work on the default
  branch in place and skip the rest of this phase.
- **Otherwise: worktree by default.** It keeps the main checkout clean and lets
  parallel sessions coexist.

**Worktree:**

1. **Provision dependencies first.** A fresh worktree is a clean checkout — gitignored
   deps and build output don't carry over, and native provisioning only runs at
   creation time, so configure it **before** creating the worktree. Detect heavy
   gitignored directories present:

   ```bash
   for d in node_modules .venv venv target build dist .next vendor .gradle .tox; do
     [ -e "$d" ] && git check-ignore -q "$d" && echo "$d"
   done
   ```

   Any found and not already in `worktree.symlinkDirectories` are added **without
   asking** to that key in the project's **`.claude/settings.local.json`** (the
   `Local` scope — per-checkout, normally gitignored — never the tracked
   `.claude/settings.json`, and never global). The `worktree` key is documented as
   valid in any settings file, including the local one. Create the file if absent;
   afterwards make sure it stays out of `git status`:

   ```bash
   git check-ignore -q .claude/settings.local.json \
     || echo ".claude/settings.local.json" >> "$(git rev-parse --git-path info/exclude)"
   ```

   Add `.env` / `.env.*` to a root `.worktreeinclude` only if they exist. That
   file has no documented alternative location, so keep it out of `git status`
   instead: if it is untracked, add `/.worktreeinclude` to
   `$(git rev-parse --git-path info/exclude)` (local, never committed). If the repo
   already tracks a `.worktreeinclude`, append to it only when a needed pattern is
   missing and mention the resulting diff in the hand-off, since that one is a
   real change. Net effect: the main checkout stays clean and no prompt is
   needed. Shape:

   ```json
   { "worktree": { "symlinkDirectories": ["node_modules", ".venv"] } }
   ```

2. **Create + enter the worktree:** call `EnterWorktree` with `name` set to the base
   name (already dash form, no `/`). This creates branch `worktree-<base-name>`, runs
   native provisioning, and switches the session into the worktree. Do **not** also
   run `branch create`.

3. **Keep the tree clean for `ship`.** A directory pattern with a trailing slash
   (e.g. `target/`) does not match a *symlink*, so a symlinked dependency directory
   can show up as untracked and trip `/git-tools:ship`'s worktree cleanliness gate.
   Inside the new worktree, exclude any such symlink locally:

   ```bash
   exclude=$(git rev-parse --git-path info/exclude)
   git ls-files --others --exclude-standard -z | while IFS= read -r -d '' d; do
     [ -L "$d" ] && { grep -qxF "/$d" "$exclude" 2>/dev/null || printf '/%s\n' "$d" >> "$exclude"; }
   done
   git status --porcelain   # expect no symlinked dependency dirs listed
   ```

   `info/exclude` is shared by every worktree of the repo, so these entries apply
   everywhere; that is acceptable because root-relative dependency dirs are
   normally ignored anyway. The `grep -qxF` guard keeps repeat runs from appending
   duplicates.

**In place on a new branch** (only when the work genuinely cannot use a worktree):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create <base-name>
```

## Phase 2 — Explore the codebase

> You MUST complete this phase. Do NOT stop after Phase 1. Do NOT print
> "suggested first steps".

**Trivial fast path.** When the change is small and obvious — a typo, a one-line or
single-file fix, a config tweak, an issue that names the exact file and change —
skip the research subagents: read the few relevant files yourself and go straight to
Phase 3 with a short inline plan.

Otherwise launch **2-3 research agents in parallel** in a single message, using
`Agent` with `subagent_type: research`. Every agent prompt MUST include the full
context — the issue title/body/labels for **all** linked issues and/or the freeform
description — so the agent can work without seeing this conversation. Pick 2-3
angles that fit:

- **Locate the code** — files, functions, types, or modules implied by the work.
  Report what each does, the change point, and surrounding signatures.
- **Find tests and related config** — existing coverage of the area, related config,
  CI, docs. Report what exists, what is missing, how the suite is structured.
- **Trace the data/call flow** — entry points, intermediate steps, dependencies, and
  edge cases.

If an agent needs the issue tracker or repo API, tell it to use `gh` or `tea`
directly, per the `git-tools:git-wait` skill's command map.

## Phase 3 — Plan

> You MUST complete this phase. Do NOT stop after Phase 2.

Call `EnterPlanMode`, then present a concrete plan for approval before any
implementation begins. Cover **all** linked issues in one plan.

- **Changes** — the specific files and line ranges, and what each change does.
  Describe the actual code change, not "fix the bug".
- **Testing** — include only when behavior changes: what tests to add or update,
  using the project's existing framework. Omit for purely cosmetic changes
  (comments, docs, formatting).
- **Risks & open questions** — edge cases and unknowns; omit when there are none.

For trivial work keep the whole plan inline and short — a few lines, not a document.
Do **not** describe committing, pushing, or opening a PR as part of the plan.

## Phase 4 — STOP & hand off after implementation (MANDATORY — NO EXCEPTIONS)

> **HARD STOP.** The moment the planned work is implemented, you STOP and hand back to
> the user. You do **NOT** `git commit`, `git push`, open or merge a pull request,
> enable auto-merge, or invoke `/git-tools:ship` or `/session:session-end` on your own
> — **no matter how obvious the next step seems, no matter that the user approved the
> plan, and even if this skill was auto-invoked.** Approving the plan authorizes
> *implementation only*, never publication. There is no exception; do not rationalize
> one.

Do **not** call `AskUserQuestion` and do **not** commit / push / PR / merge. Print a
short plain-text message and wait for the user's reply:

- One-line outcome, plus the per-file list of what changed.
- State: branch name, **work is uncommitted**, and test/build status (say so plainly
  if tests were not run).
- Caveats — known or potential problems and assumptions, stated specifically. Omit
  the line only if there are genuinely none.
- Next steps: optionally `/code-review <level> --fix`, then `/session:session-end`
  (docs, review + fix, issue sweep, ship) or `/git-tools:ship` directly.
- If issues are linked, list one closing line per issue (`Closes #N` / `Fixes #N`)
  for the PR body.

Do not tear down a worktree here — `/git-tools:ship` step 9 does that after the merge
(`/session:session-end` runs it too), or the user can leave with `ExitWorktree`.
