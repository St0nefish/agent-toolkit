---
description: "Multi-phase, multi-agent feature workflow: spec → plan → refine → divide → execute → review"
allowed-tools: Bash, Read, AskUserQuestion
---

Run a complex feature through a structured multi-agent workflow with explicit model tiering, user gates, and an automated review pass. Use this when work is non-trivial — multiple files, design ambiguity, cross-cutting concerns, or correctness-critical paths. For small fixes, prefer `/session:session-start` directly.

The workflow has seven phases. Two have hard user gates (Refine and Execute). The Review phase auto-loops on blockers up to a cap.

> **NOTE**: Copilot CLI lacks Claude's parallel sub-agent dispatch and model tiering. Run this as a single-session workflow — treat the agent-dispatch instructions below as "do the work yourself with the listed scope," dropping the parallelism. For full orchestration, use the Claude version of this plugin.
>
> **CRITICAL**: You MUST drive every phase to completion. Do NOT collapse the workflow into a single in-line plan — keep the phases distinct, present each phase's output to the user, and respect the user gates.

### Inputs

- `$ARGUMENTS` — optional initial description. If empty and no context inherited from `/session:session-start`, ask the user to describe the feature before starting Phase 1.
- Inherited context — if invoked after `/session:session-start`'s escalation, the branch is already created and the issue/description is known. Do not re-ask for a description.

### Phase 0 — Detect existing context

Before starting Phase 1, check whether prior phases of this workflow have already run on this branch:

1. Inspect the current repo directly with `git` — extract the current branch, the default branch (`origin/HEAD`, falling back to `main`/`master`), commits ahead of default, uncommitted changes, and whether the branch matches the default with no diverging commits.
2. Inspect the most recent commit messages and any `wip-`, `feat-`, `enhancement-`, `chore-`, `bug-` branch names for evidence of prior work — recent commits referencing the spec/plan, or multiple commits since the default branch.
3. If any signal of prior orchestrate work is present, ask via `AskUserQuestion`:
   - **Resume from Plan** — re-use existing exploration, regenerate the plan
   - **Resume from Divide** — plan is good, re-chunk and execute
   - **Resume from Review** — execution done, run review pass only
   - **Start fresh** — discard prior context and run all phases

   Otherwise proceed to Phase 0b with a fresh run.

### Phase 0b — Isolate in a worktree (default for fresh runs)

Orchestrate runs are heavy and long-lived — **isolate them in a git worktree by default** (assumes the `git-worktree` Copilot extension is available) so the main checkout stays clean.

- **Already isolated** — if the session is already in a worktree, or a feature branch is already checked out (inherited from `/session:session-start`, or the current branch is not the default), proceed in the current checkout. Do **not** create another worktree.
- **Fresh run on the default branch** — create the work's branch as a worktree by default. Derive a branch name (`<type>-<slug>` from the issue — no number, that lives in the PR's `Closes #N` — or `wip-<slug>` from the description) and create it with `sf_git_worktree_create` (equivalent direct flow: `git worktree add .github/worktrees/<slug> -b <branch>`). Then run **all** subsequent phases from inside the worktree by prefixing commands with `cd .github/worktrees/<slug> && …`. A fresh worktree is a clean checkout — reinstall or symlink heavy gitignored deps if the work needs them. Offer a one-key opt-out (work in place) via `AskUserQuestion`, but default to the worktree.

Then proceed to Phase 1.

### Phase 1 — Spec exploration

Goal: turn the user's description into a richer rough spec via targeted research.

1. **Identify 2-4 distinct exploration angles** based on the description. Common angles:
   - **Locate existing code** — files, functions, types, modules touched by the feature
   - **Map adjacent systems** — what consumes/produces the data, the call graph, dependencies
   - **Find relevant tests, configs, docs** — existing coverage, CI setup, conventions
   - **Surface prior art** — similar features already in the codebase, patterns to follow
   - **Identify constraints** — performance, security, compatibility, deprecated paths

2. Investigate each angle. (On Claude, these would be dispatched in parallel as Haiku/Sonnet research sub-agents. On Copilot, just walk through them serially.)

3. **Collect findings** into a rough spec the parent session can hold:
   - Code locations (file:line)
   - Adjacent systems and call paths
   - Existing tests/conventions
   - Constraints and gotchas surfaced

   Do NOT present this rough spec to the user yet — Phase 2 will refine it into a plan first.

### Phase 2 — Plan generation

Goal: produce an initial implementation plan plus an explicit list of gaps and open questions.

Produce a plan that includes:

- The full user description
- The rough spec from Phase 1 (all angles' findings, condensed)
- (a) implementation plan with file/line targets
- (b) explicit list of gaps/unknowns
- (c) open questions for the user
- (d) suggested chunking with rough parallel/serial dependency hints

Hold the plan. Do not yet present to user — Phase 3 is the discussion gate.

### Phase 3 — Refine [USER GATE]

Goal: iterate with the user until the spec and plan are agreed.

1. **Present** to the user, in the main session output:
   - Concise summary of the rough spec (2-3 sentences)
   - The implementation plan from Phase 2
   - Identified gaps and open questions, called out clearly

2. **Loop with the user** in plain conversation:
   - User adds constraints, answers questions, requests changes
   - Refine the spec/plan in-session
   - When you make refinements, summarize what changed before continuing

3. **Gate**: when the user signals approval (or after refinements you believe complete), use `AskUserQuestion` with options:
   - **Approve, proceed to divide** — proceed to Phase 4
   - **More refinement needed** — return to step 2 of this phase
   - **Stop here** — abort the workflow

   Do NOT proceed to Phase 4 without explicit approval via this gate.

### Phase 4 — Divide

Goal: break the approved plan into discrete chunks that can be executed one at a time.

1. **Detect test infrastructure** — before deciding whether tests are mandatory, run a quick check:

   ```bash
   # Probes: test directories, test files, CI test step, manifest test scripts
   ls test tests __tests__ 2>/dev/null
   git ls-files | grep -E '_test\.(go|py|rs)$|\.test\.(ts|tsx|js|jsx)$' | head -5
   git ls-files .github/workflows/ 2>/dev/null | head -5
   git ls-files | grep -E '^(package\.json|Cargo\.toml|pyproject\.toml|go\.mod)$' | head -5
   ```

   If any positive signal — test directories, conventional test files, CI workflows referencing tests, or a `test`/`check` script in package manifests — record `tests_required=true`. Otherwise `tests_required=false`.

2. **Chunk the plan** into discrete tasks. For each chunk record:
   - **Scope** — one-line description of the change
   - **Files** — specific paths touched
   - **Dependencies** — list of other chunk IDs this one depends on
   - **Tests** — if `tests_required=true` AND the chunk is not purely cosmetic, add a paired test chunk OR include test work in the chunk's scope. Skip if cosmetic-only or `tests_required=false`.

3. Hold the chunk plan for the Phase 5 gate. Do not present yet.

### Phase 5 — Execute [USER GATE]

Goal: execute the chunk plan, with failure escalation.

1. **Present the chunk plan** to the user. Use `AskUserQuestion` with options:
   - **Approve and execute** — proceed to step 2
   - **Adjust chunks** — explain what to change; revise and re-present
   - **Cancel** — abort the workflow

2. **Execute each chunk in order**, respecting dependencies.

3. **Per-chunk failure escalation** (cap 3 attempts per chunk):
   - **Attempt 1**: original approach
   - **Attempt 2**: refined approach — read the failure, clarify the success criteria, point at the specific blocker
   - **Attempt 3**: surface the chunk to the user with the full failure context

4. **After all chunks complete**, proceed to Phase 6.

### Phase 6 — Review

Goal: validate the executed work.

1. Run lint, type checks, and the test suite (if `tests_required=true`).
2. Verify spec compliance: did the work implement what the divide phase asked for?
3. Look for obvious pitfalls — error paths, null/empty handling, dead code, stale TODOs, leftover debug, regressions touching unrelated code.

If blockers found: refine the affected chunk and re-execute (Phase 5 escalation rules apply).
If concerns only: present via `AskUserQuestion`:

- **Address now** — convert each concern into a fix chunk and execute
- **Defer** — record concerns for the hand-off summary and proceed

If only nits or clean: proceed to Phase 7.

### Phase 7 — Hand-off

Goal: summarize and route to the appropriate finalization flow.

1. **Produce a final summary** for the user covering:
   - One-line outcome of the feature
   - Files changed (grouped by chunk)
   - Current state — branch name, what's committed vs. still uncommitted, test/build status
   - Test coverage added (if any)
   - Caveats — deferred concerns from Phase 6 and any known risks or follow-ups

2. **Then stop and wait for the user's free-text response.** Do NOT use `AskUserQuestion` and do NOT auto-commit, push, or open a PR. Let the user decide what's next — they may run `/git-tools:ship` (commit, push, PR, watch CI), `/session:session-end` (review-then-PR flow), ask for adjustments, or finalize manually. Just present the summary and wait in the normal chat input.

### Notes

- **Always think about whether the workflow is the right tool.** If the user invoked this for a small, well-scoped change, gently suggest `/session:session-start` instead before kicking off Phase 1.
- **Do not skip the user gates.** Phases 3 and 5 must use `AskUserQuestion`.
- **For full Claude-tier orchestration** (parallel sub-agents, Haiku/Sonnet/Opus model tiering, dedicated review-pass agents), use the Claude version of this plugin.
