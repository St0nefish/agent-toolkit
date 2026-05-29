---
name: session-orchestrate
description: "Multi-phase, multi-agent feature workflow: spec → plan → refine → divide → execute → review. Invoke when the user escalates a session-start/session-issue flow to orchestration, or asks to run a non-trivial feature (multiple files, design ambiguity, cross-cutting concerns, correctness-critical paths) through the full multi-agent workflow. For small fixes, prefer session-start."
allowed-tools: Bash, Agent, Read, Glob, Grep, AskUserQuestion, EnterWorktree, Workflow
---

Run a complex feature through a structured multi-agent workflow with explicit model tiering, user gates, and an automated review pass. Use this when work is non-trivial — multiple files, design ambiguity, cross-cutting concerns, or correctness-critical paths. For small fixes, prefer `/session:session-start` directly.

The workflow has seven phases. Two have hard user gates (Refine and Execute). The build-and-verify half (Execute + Review) runs as a single deterministic `Workflow` call.

This skill is split across two execution surfaces, and the split is deliberate:

- **Interactive, in the main session** — Phases 0–4, the Phase 3/5 gates, the Phase 6 concerns gate, and Phase 7. These need a human in the loop (refinement conversation, approvals, free-text hand-off), so they stay in the main session where you can call `AskUserQuestion` and talk to the user.
- **Headless, in a `Workflow`** — the Execute waves and the Review/blocker-auto-fix loop (`scripts/orchestrate-build.workflow.js`). This is a closed-loop machine — fan out by wave, escalate failures, review, re-dispatch blockers, re-review, cap the loop — with no human decision inside it. Expressing it as JS makes the control flow deterministic instead of something you have to police by hand.

> **CRITICAL**: You MUST drive every phase to completion. Do NOT collapse the workflow into a single in-line plan, and do NOT hand-roll the build loop in the main session — Phase 5 dispatches the `Workflow` and Phase 6 consumes its structured result. Sub-agent dispatch is the point — the user is paying for parallelism and model tiering, not for you to do everything serially in the main session.

### Inputs

- `$ARGUMENTS` — optional initial description. If empty and no context inherited from `/session:session-start`, ask the user to describe the feature before starting Phase 1.
- Inherited context — if invoked after `/session:session-start`'s escalation, the branch is already created and the issue/description is known. Do not re-ask for a description.

### Phase 0 — Detect existing context

Before starting Phase 1, check whether prior phases of this workflow have already run on this branch:

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup` to gather branch state.
2. Inspect the most recent commit messages and any `wip-`, `feat-`, `enhancement-`, `chore-`, `bug-` branch names for evidence of prior work — recent commits referencing the spec/plan, or multiple commits since the default branch.
3. If any signal of prior orchestrate work is present, ask via `AskUserQuestion`:
   - **Resume from Plan** — re-use existing exploration, regenerate the plan
   - **Resume from Divide** — plan is good, re-chunk and execute
   - **Resume from Review** — execution done, run review pass only
   - **Start fresh** — discard prior context and run all phases

   Otherwise proceed to Phase 0b with a fresh run.

### Phase 0b — Isolate in a worktree (default for fresh runs)

Orchestrate runs are heavy and long-lived — **isolate them in a git worktree by default** so the main checkout stays clean and parallel sessions can coexist.

- **Already isolated** — if the session is already in a worktree, or a feature branch is already checked out (inherited from `/session:session-start`'s escalation, or the current branch is not the default), proceed in the current checkout. Do **not** create another worktree.
- **Fresh run on the default branch** — create the work's branch as a worktree by default. Derive the name: `<type>-<slug>` from the issue (no number — that lives in the PR's `Closes #N`), or `wip-<slug>` from the description. **Before** creating, provision dependencies exactly as in `/session:session-start` Phase 2a (detect heavy gitignored dirs via `git check-ignore`; offer to write `worktree.symlinkDirectories` + `.worktreeinclude` to **project** config, asking first). Then call `EnterWorktree` with `name: <dash-form-name>` (yields branch `worktree-<name>`, provisions deps, switches the session in). Offer a one-key opt-out (work in place) via `AskUserQuestion`, but default to the worktree.

Then proceed to Phase 1.

### Phase 1 — Spec exploration

Goal: turn the user's description into a richer rough spec by dispatching cheap, parallel research agents.

1. **Identify 2-4 distinct exploration angles** based on the description. Common angles:
   - **Locate existing code** — files, functions, types, modules touched by the feature
   - **Map adjacent systems** — what consumes/produces the data, the call graph, dependencies
   - **Find relevant tests, configs, docs** — existing coverage, CI setup, conventions
   - **Surface prior art** — similar features already in the codebase, patterns to follow
   - **Identify constraints** — performance, security, compatibility, deprecated paths

2. **Dispatch all angles in parallel** in a single message, using the `Agent` tool with:
   - `subagent_type: research` (read-only)
   - `model: haiku` by default
   - **Bump to `model: sonnet`** for an angle if: codebase is unfamiliar, the angle requires synthesizing patterns rather than locating code, or the description hints at subtle cross-file relationships
   - **`model: opus`**: rarely; only for deeply tangled architectures
   - Each agent's prompt MUST include the full user description, the specific angle, and explicit "report findings concisely; do not make changes."

3. **Collect findings** into a rough spec the parent session can hold:
   - Code locations (file:line)
   - Adjacent systems and call paths
   - Existing tests/conventions
   - Constraints and gotchas surfaced

   Do NOT present this rough spec to the user yet — Phase 2 will refine it into a plan first.

### Phase 2 — Plan generation

Goal: produce an initial implementation plan plus an explicit list of gaps and open questions.

1. **Dispatch a single planning sub-agent** using the `Agent` tool with:
   - `subagent_type: Plan` (architect agent)
   - `model: sonnet` by default
   - **Bump to `model: opus`** if: cross-system design tradeoffs, significant ambiguity in the spec, novel pattern with no clear precedent in the codebase, correctness-critical (security, data integrity, concurrency, migrations)
   - **Never use `haiku`** — planning needs reasoning headroom

2. **The plan agent's prompt MUST include:**
   - The full user description
   - The rough spec from Phase 1 (all angles' findings, condensed)
   - Explicit instructions: produce (a) implementation plan with file/line targets, (b) explicit list of gaps/unknowns, (c) open questions for the user, (d) suggested chunking with rough parallel/serial dependency hints

3. **Receive and hold the plan.** Do not yet present to user — Phase 3 is the discussion gate.

### Phase 3 — Refine [USER GATE]

Goal: iterate with the user until the spec and plan are agreed.

1. **Present** to the user, in the main session output:
   - Concise summary of the rough spec (2-3 sentences)
   - The implementation plan from Phase 2
   - Identified gaps and open questions, called out clearly

2. **Loop with the user** in plain conversation:
   - User adds constraints, answers questions, requests changes
   - You refine the spec/plan in-session (no agent dispatch needed for small refinements; re-dispatch a planning agent only if the user requests substantial re-planning)
   - When you make refinements, summarize what changed before continuing

3. **Gate**: when the user signals approval (or after refinements you believe complete), use `AskUserQuestion` with options:
   - **Approve, proceed to divide** — proceed to Phase 4
   - **More refinement needed** — return to step 2 of this phase
   - **Stop here** — abort the workflow

   Do NOT proceed to Phase 4 without explicit approval via this gate.

### Phase 4 — Divide

Goal: break the approved plan into discrete chunks that can be dispatched to execution agents.

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
   - **ID** — a short stable identifier (`c1`, `c2`, …). The Workflow keys execution, review, and re-dispatch on it, so it must be unique and stable across the run.
   - **Scope** — one-line description of the change
   - **Files** — specific paths touched. Chunks **within the same wave must own disjoint files** — they run in parallel against one working tree, so overlapping files would clobber each other. If two chunks must touch the same file, put them in different waves with a dependency.
   - **Dependencies** — list of other chunk IDs this one depends on (for serial ordering)
   - **Tests** — if `tests_required=true` AND the chunk is not purely cosmetic, add a paired test chunk OR include test work in the chunk's scope (set its `tests` flag, with optional `testScope` guidance). Skip if cosmetic-only or `tests_required=false`.
   - **Suggested model tier** — Haiku / Sonnet / Opus, applying these heuristics:
     - **Haiku** — mechanical change, well-established pattern in the codebase, single-file scope, clear acceptance criteria (rename, add import, simple test case, copy-pattern)
     - **Sonnet (default)** — standard dev work: new feature following codebase conventions, moderate refactor, multi-file but bounded
     - **Opus** — novel algorithm, complex state machine, critical correctness path (auth, crypto, payments, transactions, migrations, concurrency primitives), deep refactor touching many subsystems, or chunks requiring lots of context
   - **Opus review** — set an `opusReview` flag on the chunk when it warrants the senior review pass in Phase 6: it was tagged Opus-tier above, its paths match correctness-critical patterns (auth, crypto, payments, transactions, migrations, concurrency primitives), the spec called out correctness/security, or it involves a novel algorithm or non-trivial state machine. Leave it off for trivial chunks.

3. **Identify parallelization** — group chunks into waves. A wave is a set of chunks with no dependencies on each other (within the wave); they will be dispatched in parallel. Waves run serially, with each later wave allowed to depend on completed earlier waves.

4. **Hold the chunk plan** for the Phase 5 gate. Do not present yet — present at the gate.

### Phase 5 — Execute [USER GATE → Workflow]

Goal: get the user's approval, then hand the approved chunk plan to the build-and-verify `Workflow`.

1. **Present the chunk plan** to the user. Use `AskUserQuestion` with options:
   - **Approve and dispatch** — proceed to step 2
   - **Adjust chunks** — explain what to change; revise and re-present
   - **Adjust model tiers** — let the user override per-chunk model picks
   - **Cancel** — abort the workflow

   This gate is also the spend gate: approving here is what authorizes the `Workflow` to spin up a background fleet. Do not dispatch without it — even if this skill was auto-invoked by the model rather than the user.

2. **Construct the Workflow `args`** from the approved chunk plan. Build a JSON object:

   ```json
   {
     "description": "<the user's feature description>",
     "plan": "<the agreed implementation plan, as markdown>",
     "testsRequired": <true|false from Phase 4 step 1>,
     "waves": [
       [ { "id": "c1", "scope": "...", "files": ["..."], "model": "sonnet", "tests": false, "opusReview": false } ],
       [ { "id": "c2", "scope": "...", "files": ["..."], "model": "opus",   "tests": true, "testScope": "...", "opusReview": true } ]
     ]
   }
   ```

   `waves` is dependency-ordered: each inner array is one wave, dispatched in parallel; waves run serially. Carry every field from the Phase 4 chunk record (`id`, `scope`, `files`, `model`, `tests`, optional `testScope`, `opusReview`).

3. **Dispatch the Workflow.** Call the `Workflow` tool with:
   - `scriptPath: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate-build.workflow.js`
   - `args: <the object from step 2>` (pass it as an actual JSON value, not a stringified blob)

   The Workflow runs headless: it executes the waves with per-chunk failure escalation (attempt 1 = chunk tier; attempt 2 = same tier + failure-refined prompt; attempt 3 = bumped tier), then reviews every executed chunk (one Sonnet reviewer each, plus one Opus reviewer over the `opusReview` subset), and **auto-fixes blockers** by re-dispatching affected chunks with the reviewer feedback and re-reviewing only those — capped at 2 review iterations. Concerns and nits are reported, never auto-fixed. It edits the session's working tree (the Phase 0b worktree, if one was created), so no per-agent isolation is needed. You can watch progress via `/workflows`.

4. **When the Workflow returns**, it gives you a structured result — proceed to Phase 6 to consume it:

   ```json
   {
     "iterations": 1,
     "hitReviewCap": false,
     "perChunk": [ { "chunkId": "c1", "ok": true, "attempts": 1, "model": "sonnet", "summary": "...", "testsPassed": true } ],
     "filesChanged": ["..."],
     "clean": ["c1"],
     "unresolvedBlockers": [],
     "concerns": [ { "chunkId": "c2", "severity": "concern", "title": "...", "detail": "...", "file": "..." } ],
     "nits": [ { "chunkId": "c1", "severity": "nit", "title": "..." } ]
   }
   ```

### Phase 6 — Consume review findings

Goal: act on the `Workflow`'s structured result. The blocker auto-fix loop already ran headlessly inside the Workflow; this phase handles only the decisions that need a human.

1. **If `unresolvedBlockers` is non-empty** (`hitReviewCap` is true — the auto-fix loop hit its 2-iteration cap with blockers still standing): surface every remaining blocker to the user with full context (chunk, title, detail, file, and the chunk's `perChunk` summary). Do not silently retry beyond the cap. Let the user decide — fix manually, re-run a targeted Workflow on those chunks, or accept and move on.

2. **Else if `concerns` is non-empty**: present them via `AskUserQuestion`:
   - **Address now** — treat the concerns as a fresh, small chunk plan (one wave, one chunk per concern fix, tiers as appropriate) and re-dispatch the Workflow with those chunks. Then re-enter Phase 6 on the new result.
   - **Defer** — record the concerns for the Phase 7 hand-off summary and proceed.

3. **Else (only `nits` or fully clean)**: note any nits for the hand-off summary and proceed to Phase 7.

Carry `perChunk`, `filesChanged`, `clean`, deferred `concerns`, and `nits` forward — Phase 7's summary draws on them.

### Phase 7 — Hand-off

Goal: summarize and route to the appropriate finalization flow.

1. **Produce a final summary** for the user covering:
   - One-line outcome of the feature
   - Files changed (grouped by chunk)
   - Current state — branch name, what's committed vs. still uncommitted, test/build status
   - Test coverage added (if any)
   - Caveats — deferred concerns from Phase 6, chunks surfaced for manual handling, and any known risks or follow-ups

2. **Then stop and wait for the user's free-text response.** Do NOT use `AskUserQuestion` and do NOT auto-commit, push, or open a PR. Let the user decide what's next — they may run `/git-tools:ship` (commit, push, PR, watch CI), `/session:session-end` (review-then-PR flow), ask for adjustments, or finalize manually. Just present the summary and wait in the normal chat input.

If this run created a worktree (Phase 0b), note that its teardown is deferred: `/session:session-end` removes it after the PR merges, or the user can leave it and exit later with `ExitWorktree`. Do not tear it down here.

### Notes

- **Always think about whether the workflow is the right tool.** If the user invoked this for a small, well-scoped change, gently suggest `/session:session-start` instead before kicking off Phase 1.
- **Do not skip the user gates.** Phases 3 and 5 must use `AskUserQuestion`, and Phase 5's gate is the spend gate for the `Workflow`. The Phase 6 concerns step also gates via `AskUserQuestion`. The blocker auto-fix loop inside the `Workflow` is the only place work advances without an explicit gate.
- **The build loop lives in the `Workflow`, not the main session.** Do not re-implement Execute or the review/blocker loop with inline `Agent` calls — construct the `args` and dispatch `scripts/orchestrate-build.workflow.js`. Self-contained prompts (full context per agent), parallel wave dispatch, failure escalation, and review dedupe are all handled inside the script.
- **Sub-agent prompts are self-contained.** This still applies to the phases that *do* dispatch inline — every Phase 1 research `Agent` and the Phase 2 planning `Agent` must carry enough context to succeed without seeing the parent conversation.
- **Parallel dispatch matters for the inline phases.** Within a Phase 1 angle set, issue all `Agent` calls in a single message so they run concurrently. (Phase 5/6 parallelism is the `Workflow`'s job.)
- **Keep `args` and the script in sync.** If you change the chunk-record shape in Phase 4, update both the Phase 5 `args` contract and the `args` documentation at the top of `orchestrate-build.workflow.js`.
