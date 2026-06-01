# Begin-work spine

The shared playbook for the lightweight session entrypoints (`session-start` and
`session-issue`). Both doors differ only in **how the work is chosen** — once the
work is identified, they run these phases identically. This is the single-session
counterpart to `session-orchestrate`: same shape (isolate → explore → plan →
hand-off), without the multi-agent execute/review tail.

> **CRITICAL**: You MUST drive this through to a plan. After the branch exists you
> launch research agents and enter plan mode. NEVER print "suggested first steps"
> or ask "ready to start?" — the flow does not end until you have called
> `EnterPlanMode` with a plan built from real code exploration.
>
> **EQUALLY CRITICAL — the other end of the flow**: after the approved work is
> implemented you **STOP** (Phase 5) and wait for the user. You never commit, push,
> open/merge a PR, or finalize on your own. Plan approval ≠ permission to publish.

## Inputs (supplied by the calling door)

The calling skill has already established:

- **Context** — a freeform description (from `session-start`) and/or a linked issue
  with its full title, body, and labels (from `session-issue`).
- **Base branch name** — `<type>-<slug>` when an issue is linked, or
  `wip-<slug>` for freeform work. The branch does not carry the issue number; the
  linkage is the PR's `Closes #N`.

If you reach this spine without a base name or any context, stop and return to the
calling door — it owns target selection.

## Phase 1 — Isolate

Decide whether to isolate the new branch in a git worktree. **Skip this phase
entirely** when resuming an existing branch, or when already inside a worktree
(`git rev-parse --git-common-dir` resolves outside `git rev-parse --show-toplevel`,
or `git worktree list` shows you are not in the main worktree) — just proceed on the
current checkout.

**Default to a worktree for substantial new work** — it keeps the main checkout
clean and lets parallel sessions coexist. Lean toward a worktree when any hold: the
current branch has uncommitted changes that would be disturbed, the user asked for
parallel/isolated work, or the work is a non-trivial feature. Create the branch
**in place** for trivial one-file fixes, or if the user prefers the current checkout.
If genuinely unsure, offer the choice via `AskUserQuestion` (Worktree / In place).

**In place:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch create <base-name>
```

**Worktree:**

1. **Provision dependencies first (one-time per repo).** A fresh worktree is a clean
   checkout — gitignored build artifacts and deps don't carry over, and native
   provisioning only runs at creation time, so configure it **before** creating the
   worktree. Detect heavy gitignored directories present:

   ```bash
   for d in node_modules .venv venv target build dist .next vendor .gradle .tox; do
     [ -e "$d" ] && git check-ignore -q "$d" && echo "$d"
   done
   ```

   If any are found and not already in `worktree.symlinkDirectories`, offer via
   `AskUserQuestion` to write them to that key in the **project** `.claude/settings.json`,
   and to add common local files (`.env`, `.env.*`) to a root `.worktreeinclude`. Ask
   before writing; only touch project-level config, never global. Recommended shape:

   ```json
   { "worktree": { "symlinkDirectories": ["node_modules", ".venv"] } }
   ```

2. **Create + enter the worktree:** call `EnterWorktree` with `name` set to the
   base name (already in dash form — `<type>-<slug>` or `wip-<slug>` — so it needs
   no conversion and contains no `/`). This creates branch `worktree-<name>`, runs
   native provisioning, and switches the session into the worktree. Do **not** also
   run `branch create` — `EnterWorktree` creates the branch. (The `worktree-` prefix
   is expected and harmless.)

## Phase 2 — Escalate to orchestrate? (gate)

Before exploring, judge whether the work is substantial enough to warrant the
heavier `/session:session-orchestrate` workflow (multi-agent dispatch, model
tiering, an automated review pass). **Lightweight is the default, and most work
stays lightweight.** Do not surface this choice on every run — a needless
lightweight-vs-orchestrate menu on routine work is the exact thing to avoid. Your
first job is to decide *whether the question is even worth asking*, and only ask
when the answer is genuinely "this is a big task."

**Step 1 — Assess scope yourself** from everything you already know (the freeform
description and/or the issue title, body, and labels). Read it as *complex* only
when **two or more** of these signals hold:

- touches multiple files, modules, or subsystems; a cross-cutting concern
- real design ambiguity — more than one viable approach, or the approach is unclear
- correctness-critical or security-sensitive path where being wrong is expensive
- a long or multi-part spec: ≳300-word body, several acceptance criteria/checkboxes
- keywords like `refactor`, `redesign`, `architecture`, `migration`, `system`, or a
  multi-step `feature`

**Step 2 — Act on the assessment:**

- **Simple or moderate work** (the common case — a bug fix, a single contained
  feature, a doc change, a scoped edit, anything where the path is reasonably
  obvious): **do not ask and do not mention orchestrate.** Assume lightweight and
  continue straight to Phase 3.
- **Genuinely complex work** (two or more signals above): ask **once** via
  `AskUserQuestion`:
  - **Stay on lightweight flow** — continue to Phase 3 here.
  - **Escalate to orchestrate** — invoke `/session:session-orchestrate` with the
    issue/description as context. The branch (and worktree, if created) is already
    set up, so orchestrate proceeds in this checkout. Do NOT run Phases 3-4 below.

If you ask and the user escalates, hand off and stop. Otherwise — whether you
skipped the question or the user chose to stay — continue to Phase 3.

## Phase 3 — Explore the codebase (MANDATORY)

> You MUST complete this phase. Do NOT stop after Phase 1/2. Do NOT print
> "suggested first steps".

Launch **2-3 research agents in parallel** in a single message. Use `Agent` with
`subagent_type: research`. Every agent prompt MUST include the full context — the
issue title/body/labels and/or the freeform description — so the agent can work
without seeing this conversation. Pick 2-3 angles based on what the work describes:

- **Locate the code** — find the files, functions, types, or modules implied by the
  work. Read them fully. Report what each does, the change point, and relevant
  surrounding signatures.
- **Find tests and related config** — existing test coverage of the affected area,
  related config, CI setup, docs. Report what exists, what's missing, how the suite is
  structured.
- **Trace the data/call flow** — follow the call chain or data flow through the area.
  Report entry points, intermediate steps, dependencies, and edge cases.

If an agent needs the issue tracker or repo API, it MUST use
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli` — never raw `gh`/`tea`.

## Phase 4 — Plan (MANDATORY)

> You MUST complete this phase. Do NOT stop after Phase 3.

Call `EnterPlanMode`. Using the agents' findings, produce a concrete implementation
plan with all of these sections:

### Changes

- The specific files and line ranges to change.
- What each change does and how — describe the actual code change, not "fix the bug".

### Testing (REQUIRED)

- What tests to add or update — unit, integration, or script-level as fits the
  codebase. Use the project's existing framework/runner; if none, add lightweight
  validation proportional to the change.
- Only skip tests if the change is purely cosmetic (comments, docs, formatting) —
  otherwise tests are mandatory.

### Risks & open questions

- Edge cases, breaking changes, unknowns.

### Post-implementation hand-off

- The plan MUST state that, once the work is implemented, you will run the mandatory
  STOP gate in Phase 5 below: present a summary plus caveats and wait for the user. Do
  **not** describe committing, pushing, or opening a PR as part of "the plan" — those
  are a separate, user-initiated step that happens only after the Phase 5 hand-off.

Present the plan for user approval before any implementation begins.

## Phase 5 — STOP & hand off after implementation (MANDATORY — NO EXCEPTIONS)

> **HARD STOP.** The moment the planned work is implemented, you STOP and hand back to
> the user. You do **NOT** `git commit`, `git push`, open or merge a pull request,
> enable auto-merge, or invoke `/git-tools:ship` or `/session:session-end` on your own
> — **no matter how obvious the next step seems, no matter that the user approved the
> plan, and even if this skill was auto-invoked.** Approving the plan authorizes
> *implementation only*, never publication. Finalizing is a separate, explicit,
> user-initiated act. There is no exception to this; do not rationalize one.

When the work is done:

1. Do **NOT** call `AskUserQuestion` (no menu) and do **NOT** commit / push / PR /
   merge. Print a plain-text wrap-up, then wait for the user's free-text reply in the
   normal chat input. The wrap-up MUST contain, in this order:
   - **Summary** — one-line outcome plus a per-file list of what changed.
   - **Current state** — branch name, what is committed vs. still uncommitted, and
     test/build status (say so plainly if tests were not run).
   - **Caveats** — be up front and specific about known *or potential* problems:
     known bugs, uncovered edge cases, assumptions you made, incomplete pieces, and
     follow-up work. If you are unsure something works, say so explicitly. Do not
     downplay or omit risks to make the result look finished.
2. Then let the user decide what is next — they may run `/git-tools:ship`
   (commit → push → PR → watch → merge), `/session:session-end` (the review-gated PR
   flow), ask for changes, or finalize by hand. If an issue is linked and they later
   commit or open a PR, include `Closes #N` (or `Fixes #N` for bugs) so the issue
   auto-closes on merge.
3. If this run created a worktree, note that teardown is deferred: `/session:session-end`
   removes it after the PR merges, or the user can exit later with `ExitWorktree`. Do
   not tear it down here.
