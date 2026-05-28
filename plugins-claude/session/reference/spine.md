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

## Inputs (supplied by the calling door)

The calling skill has already established:

- **Context** — a freeform description (from `session-start`) and/or a linked issue
  with its full title, body, and labels (from `session-issue`).
- **Base branch name** — `<type>/<N>-<slug>` when an issue is linked, or
  `wip/<slug>` for freeform work.

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

2. **Create + enter the worktree:** call `EnterWorktree` with `name` set to a
   dash-form of the base name — `<type>-<N>-<slug>` for issues, `wip-<slug>` for
   freeform. This creates branch `worktree-<name>`, runs native provisioning, and
   switches the session into the worktree. Do **not** also run `branch create` —
   `EnterWorktree` creates the branch. (The `worktree-` prefix is expected; the
   session scripts parse the issue number through it.)

## Phase 2 — Escalate to orchestrate? (gate)

Before exploring, decide whether the work warrants the heavier
`/session:session-orchestrate` workflow (multi-agent dispatch, model tiering, an
automated review pass):

- **Always offer** when the user took the freeform-description path (`session-start`).
- **Offer for issues** when the body suggests non-trivial scope: long body
  (≳300 words), multiple acceptance criteria/checkboxes, multiple files implied, or
  keywords like `refactor`, `redesign`, `system`, `architecture`, `migration`,
  `feature`.
- **Skip the offer** for clearly small work: typo fixes, doc tweaks, single-line
  changes.

When the criteria say to offer, ask via `AskUserQuestion`:

- **Stay on lightweight flow** — continue to Phase 3 here.
- **Escalate to orchestrate** — invoke `/session:session-orchestrate` with the
  issue/description as context. The branch (and worktree, if created) is already set
  up, so orchestrate proceeds in this checkout. Do NOT run Phases 3-4 below.

If the user escalates, hand off and stop. Otherwise continue.

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

### Post-implementation wrap-up (do NOT force a menu)

- When the work is done, do NOT use `AskUserQuestion` and do NOT auto-commit. Print a
  plain-text wrap-up, then wait for the user's response in the normal chat input. It
  MUST cover:
  - **Summary** — one-line outcome plus a per-file list of what changed.
  - **Current state** — branch name, what's committed vs. still uncommitted, and
    test/build status.
  - **Caveats** — known risks, uncovered edge cases, incomplete pieces, follow-ups.
- Then let the user decide what's next (they may run `/git-tools:ship` to push/PR/merge,
  `/session:session-end` for the review-then-PR flow, request adjustments, or finalize
  manually). If an issue is linked and they later commit or open a PR, include
  `Closes #N` (or `Fixes #N` for bugs) so the issue auto-closes on merge.
- If this run created a worktree, note that teardown is deferred: `/session:session-end`
  removes it after the PR merges, or the user can exit later with `ExitWorktree`. Do
  not tear it down here.

Present the plan for user approval before any implementation begins.
