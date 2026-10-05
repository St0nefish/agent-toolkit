# Begin-work spine

The shared playbook for the lightweight session entrypoints (`session-start` and
`session-issue`). Both doors differ only in **how the work is chosen** — once the
work is identified, they run these phases identically: resolve target → isolate →
explore → plan → hand-off.

**Lightweight is the only flow here.** Do not ask "lightweight vs orchestrate", and
do not ask about worktree vs in-place, dependency symlinks, latency, or scope —
decide silently using the defaults below. Ask only when something is genuinely
ambiguous about **what to build** (the exceptions are the explicit prompts in Phase 0
validation and Phase 1 collisions / dirty default branch). If the user asks for a
heavier multi-agent flow, mention once that `/session:session-orchestrate` exists and
invoke it; never raise it unprompted.

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
  `session-start` description or its related-issue lookup) or a **freeform
  description**.
- Whether the door already knows the hosting `platform` (reuse it; never detect
  twice).
- `continuing` (both doors determine it): **true** when the current branch is not the
  default branch and has commits ahead of it or uncommitted work; otherwise false.
  When true, skip Phase 1's Isolate steps and keep the current branch.

If you reach this spine with neither issues nor a description, stop and return to
the calling door — it owns target selection.

## Phase 0 — Resolve target

Run this once, for both doors.

1. **Fetch and validate issues** (skip for freeform work). Detect the platform once
   unless the door already did, then fetch **every** referenced issue:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
   ```

   - **github:** `gh issue view <N> --json number,title,body,state,labels,comments`
   - **gitea:** `tea issues <N> --output json`

   For anything beyond issue viewing (PR create, CI runs, state values), use the
   command map in the `git-tools:git-wait` skill rather than guessing flags.
   Keep each issue's title, body, and labels as context for the whole session.

   **Validate each issue.** If the fetch fails, the state is not open, or the number
   is a pull request (not an issue), tell the user and either drop that number or
   stop — ask which when it is not obvious. Also warn (and ask whether to proceed)
   when an issue is already claimed: it appears in
   `git config --get-regexp 'branch\..*\.session-issues'` or has an open PR.

2. **Pick the branch type** from labels. Compare case-insensitively on the label's
   **last path segment** (`kind/bug` and `Kind/Enhancement` match `bug` and
   `enhancement`). With several issues, a `bug` label on any of them wins; otherwise
   use the first issue's labels:
   - `bug`, `fix` → `bug`
   - `enhancement`, `feature`, `improvement` → `enhancement`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore`
   - no matching label → `feature`

3. **Name the work.**
   - **Continuing** (`continuing` is true): do **not** build a new base name or
     branch type. The session name is the current branch name with any leading
     `worktree-` stripped.
   - **Otherwise** build the base name: issue-linked `<type>-<slug>`; freeform
     `wip-<slug>`. The slug is a kebab-case 3-5 word summary (of the first issue's
     title, or the common theme when several issues are bundled; of the description
     for freeform). The branch never encodes issue numbers — linkage is the closing
     lines in the PR body.

     Actual branch names: created in place, the branch is `<base-name>`; created via
     `EnterWorktree` (Phase 1), it is `worktree-<base-name>`. The session name is
     `<base-name>`.

4. **Closing lines.** One line per issue: `Fixes #N` for `bug` issues, `Closes #N`
   otherwise. Phase 1 persists them.

## Phase 1 — Isolate, record, rename

**Skip the Isolate steps** (everything through "In place on a new branch") when
`continuing` is true, or when already inside a linked worktree. Detect the latter
with:

```bash
git_dir=$(realpath "$(git rev-parse --path-format=absolute --git-dir)")
git_common_dir=$(realpath "$(git rev-parse --path-format=absolute --git-common-dir)")
[ "$git_dir" != "$git_common_dir" ] && echo "linked worktree"
```

(`realpath` avoids false differences from symlinked paths; same test as
`/git-tools:ship` step 0.) Then go straight to "Record issue linkage" and "Rename the
session" below on the current checkout.

Decide silently:

- **Repo's `CLAUDE.md` says to work directly on the default branch / master** (as
  `homelab-admin` does): do not create a branch or worktree; work on the default
  branch in place and skip the rest of Isolate. There is no branch to record
  linkage on; skip that step.
- **Otherwise: worktree by default.** It keeps the main checkout clean and lets
  parallel sessions coexist.

**Before creating anything:**

- **Dirty default branch.** If on the default branch with uncommitted changes, warn
  once that those edits stay in the main checkout (they are not carried into the
  worktree) and ask whether to proceed with the worktree or work in place. This is a
  genuine ambiguity, so ask.
- **Name collisions.** Check for `<base-name>` and `worktree-<base-name>`:

  ```bash
  git worktree list
  git branch --list "<base-name>" "worktree-<base-name>"
  ```

  If either exists, offer to **resume** it (enter the existing worktree via
  `EnterWorktree` with `path`, or `git switch` to the branch) or to use a short
  numeric suffix (`<base-name>-2`). Decide silently only when unambiguous (e.g. it
  is clearly stale or clearly this same work); ask when it could be someone's other
  work. If you resume, treat the run as `continuing`.

**Worktree:**

1. **Provision dependencies first.** A fresh worktree is a clean checkout — gitignored
   deps don't carry over, and native provisioning only runs at creation time, so
   configure it **before** creating the worktree. Symlink **dependency directories
   only** — never build output (`target`, `build`, `dist`, `.next`, `.gradle`,
   `.tox`), which is stale or wrong in another checkout. Detect those present:

   ```bash
   for d in node_modules .venv venv vendor; do
     [ -e "$d" ] && git check-ignore -q "$d" && echo "$d"
   done
   ```

   Add the detected names **without asking** to `worktree.symlinkDirectories` in the
   project's **`.claude/settings.local.json`** (`Local` scope — per-checkout,
   normally gitignored; never the tracked `.claude/settings.json`, never global).
   Merge with `jq`, unioning with any existing list and preserving all other keys;
   create the file if absent. With the detected names in `$dirs` as a JSON array
   (e.g. `'["node_modules",".venv"]'`):

   ```bash
   f=.claude/settings.local.json
   mkdir -p .claude
   [ -s "$f" ] || echo '{}' > "$f"
   jq --argjson d "$dirs" \
     '.worktree.symlinkDirectories = ((.worktree.symlinkDirectories // []) + $d | unique)' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
   git check-ignore -q "$f" \
     || echo "/$f" >> "$(git rev-parse --path-format=absolute --git-path info/exclude)"
   ```

   Skip this step if no dependency directory was detected. Add `.env` / `.env.*` to a
   root `.worktreeinclude` only if they exist. That file has no documented
   alternative location, so keep it out of `git status` instead: if it is untracked,
   add `/.worktreeinclude` to the same `info/exclude`. If the repo already tracks a
   `.worktreeinclude`, append to it only when a needed pattern is missing and
   mention the resulting diff in the hand-off, since that one is a real change.

2. **Create + enter the worktree:** call `EnterWorktree` with `name` set to the base
   name (already dash form, no `/`). This creates branch `worktree-<base-name>`, runs
   native provisioning, and switches the session into the worktree. Do **not** also
   run `branch create`.

   This assumes `worktree.symlinkDirectories` is read at `EnterWorktree` time. As a
   fallback, for each detected dependency directory missing in the new worktree,
   create it yourself: `ln -s "<main-checkout>/<dir>" "<dir>"`.

3. **Keep the tree clean for `ship`.** A directory pattern with a trailing slash
   (e.g. `node_modules/`) does not match a *symlink*, so a symlinked dependency
   directory can show up as untracked and trip `/git-tools:ship`'s worktree
   cleanliness gate. Inside the new worktree, exclude **only the dependency-directory
   names detected in step 1** (not every untracked symlink):

   ```bash
   exclude=$(git rev-parse --path-format=absolute --git-path info/exclude)
   for d in $detected; do   # names from step 1, e.g. node_modules .venv
     [ -L "$d" ] && { grep -qxF "/$d" "$exclude" 2>/dev/null || printf '/%s\n' "$d" >> "$exclude"; }
   done
   git status --porcelain   # expect no symlinked dependency dirs listed
   ```

   `info/exclude` is shared by every worktree of the repo, so these entries apply
   everywhere; that is acceptable because root-relative dependency dirs are
   normally ignored anyway. The `grep -qxF` guard prevents duplicates.

**In place on a new branch** (only when the work genuinely cannot use a worktree):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create <base-name>
```

**Record issue linkage** (always, once the branch exists — including when
`continuing`; skip when there are no linked issues or no branch). Store the closing
lines from Phase 0 step 4 as one comma-separated value, one entry per issue:

```bash
git config "branch.$(git branch --show-current).session-issues" "Closes #12,Fixes #13"
```

The Phase 4 hand-off, `/session:session-end`, and `session-orchestrate` read this
key. When `continuing`, union with any existing value rather than overwriting.

**Rename the session** (always, last — `rename-session` keys off the current
directory, which `EnterWorktree` changes). Use the session name from Phase 0 step 3:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/rename-session "<session-name>"
```

A rename failure is non-fatal: warn and continue. When working on the default
branch in place with no meaningful name, skip the rename (warn only).

## Phase 2 — Explore the codebase

> You MUST complete this phase. Do NOT stop after Phase 1. Do NOT print
> "suggested first steps".

**Trivial fast path.** When the change is small and obvious — a typo, a one-line or
single-file fix, a config tweak, an issue that names the exact file and change —
skip the research subagents: read the few relevant files yourself and go straight to
Phase 3 with a short plan inside `EnterPlanMode`.

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
- **Final bullet, always last, verbatim:**
  "After implementing: STOP and hand off (spine Phase 4) - no commit, push, or PR."

For trivial work keep the whole plan short — a few lines, not a document. Do **not**
describe committing, pushing, or opening a PR as part of the plan beyond that final
bullet.

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
- State, from real commands (`git status --short`, `git rev-list --count
  @{upstream}..HEAD` or against the default branch): branch name, `uncommitted
  changes: yes/no`, commits ahead of the default branch, and test/build status (say
  so plainly if tests were not run).
- Caveats — known or potential problems and assumptions, stated specifically. Omit
  the line only if there are genuinely none.
- Next steps: optionally `/code-review <level> --fix` (e.g. `/code-review high
  --fix`), then `/session:session-end` (docs, review + fix, issue sweep, ship) or
  `/git-tools:ship` directly.
- If issues are linked, list one closing line per issue (`Closes #N` / `Fixes #N`)
  for the PR body — read them from `git config
  branch.$(git branch --show-current).session-issues` (comma-separated) if they are
  no longer in context.
- **Worked on the default branch in place** (repo `CLAUDE.md` says so): there is no
  feature branch; say that `/session:session-end` or `/git-tools:ship` will run from
  the default branch.

Do not tear down a worktree here — `/git-tools:ship` step 9 does that after the merge
(`/session:session-end` runs it too), or the user can leave with `ExitWorktree`.
