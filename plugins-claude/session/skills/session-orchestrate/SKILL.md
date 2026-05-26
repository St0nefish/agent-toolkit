---
disable-model-invocation: true
name: session-orchestrate
description: "Multi-phase, multi-agent feature workflow: spec → plan → refine → divide → execute → review"
allowed-tools: Bash, Agent, Read, Glob, Grep, AskUserQuestion
---

Run a complex feature through a structured multi-agent workflow with explicit model tiering, user gates, and an automated review pass. Use this when work is non-trivial — multiple files, design ambiguity, cross-cutting concerns, or correctness-critical paths. For small fixes, prefer `/session:session-start` directly.

The workflow has seven phases. Two have hard user gates (Refine and Execute). The Review phase auto-loops on blockers up to a cap.

> **CRITICAL**: You MUST drive every phase to completion. Do NOT collapse the workflow into a single in-line plan. Sub-agent dispatch is the point — the user is paying for parallelism and model tiering, not for you to do everything serially in the main session.

### Inputs

- `$ARGUMENTS` — optional initial description. If empty and no context inherited from `/session:session-start`, ask the user to describe the feature before starting Phase 1.
- Inherited context — if invoked after `/session:session-start`'s escalation, the branch is already created and the issue/description is known. Do not re-ask for a description.

### Phase 0 — Detect existing context

Before starting Phase 1, check whether prior phases of this workflow have already run on this branch:

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup` to gather branch state.
2. Inspect the most recent commit messages and any `wip/`, `feat/`, `enhancement/`, `chore/`, `bug/` branch names for evidence of prior work — recent commits referencing the spec/plan, multiple commits since the default branch, or a checkpoint comment on the linked issue.
3. If any signal of prior orchestrate work is present, ask via `AskUserQuestion`:
   - **Resume from Plan** — re-use existing exploration, regenerate the plan
   - **Resume from Divide** — plan is good, re-chunk and execute
   - **Resume from Review** — execution done, run review pass only
   - **Start fresh** — discard prior context and run all phases

   Otherwise proceed to Phase 1 with a fresh run.

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
   - **Scope** — one-line description of the change
   - **Files** — specific paths touched
   - **Dependencies** — list of other chunk IDs this one depends on (for serial ordering)
   - **Tests** — if `tests_required=true` AND the chunk is not purely cosmetic, add a paired test chunk OR include test work in the chunk's scope. Skip if cosmetic-only or `tests_required=false`.
   - **Suggested model tier** — Haiku / Sonnet / Opus, applying these heuristics:
     - **Haiku** — mechanical change, well-established pattern in the codebase, single-file scope, clear acceptance criteria (rename, add import, simple test case, copy-pattern)
     - **Sonnet (default)** — standard dev work: new feature following codebase conventions, moderate refactor, multi-file but bounded
     - **Opus** — novel algorithm, complex state machine, critical correctness path (auth, crypto, payments, transactions, migrations, concurrency primitives), deep refactor touching many subsystems, or chunks requiring lots of context

3. **Identify parallelization** — group chunks into waves. A wave is a set of chunks with no dependencies on each other (within the wave); they will be dispatched in parallel. Waves run serially, with each later wave allowed to depend on completed earlier waves.

4. **Hold the chunk plan** for the Phase 5 gate. Do not present yet — present at the gate.

### Phase 5 — Execute [USER GATE]

Goal: dispatch sub-agents to execute the chunk plan, with failure escalation.

1. **Present the chunk plan** to the user. Use `AskUserQuestion` with options:
   - **Approve and dispatch** — proceed to step 2
   - **Adjust chunks** — explain what to change; revise and re-present
   - **Adjust model tiers** — let the user override per-chunk model picks
   - **Cancel** — abort the workflow

2. **Dispatch each wave**:
   - Within a wave, dispatch all chunks **in parallel** by issuing all `Agent` calls in a single message. Each `Agent` call uses:
     - `subagent_type: general-purpose`
     - `model: <tier from chunk plan>`
     - `prompt`: a self-contained brief including the user description, the agreed plan, this chunk's scope/files/test requirements, success criteria, and the convention "report what you did and any issues encountered; if blocked, describe the blocker rather than guessing"
   - **Wait for the wave to complete**, then dispatch the next wave. Never start a later wave before its dependencies finish.

3. **Per-chunk failure escalation** (cap 3 attempts per chunk):
   - **Attempt 1**: original model + original prompt
   - **Attempt 2**: same model + parent-refined prompt — read the failure output, add context about why it failed, clarify the success criteria, point at the specific blocker
   - **Attempt 3**: bumped tier (Haiku→Sonnet→Opus) + refined prompt
   - After Attempt 3 fails, surface the chunk to the user with the full failure context. Do not silently retry beyond the cap.

4. **After all waves complete**, proceed to Phase 6.

### Phase 6 — Review (automated, auto-loops)

Goal: validate the executed work with reviewer sub-agents and auto-loop on blockers.

1. **Dispatch Sonnet bulk reviewers in parallel**, one per executed chunk (or one per logical group if chunks are tightly coupled). Each reviewer uses:
   - `subagent_type: general-purpose`
   - `model: sonnet`
   - `prompt` covering: codebase conventions (naming, file layout, imports, idioms), lint/type checks pass, test suite passes if `tests_required=true`, spec compliance (does it implement what the divide phase asked for?), obvious pitfalls (error paths, null/empty handling, dead code, stale TODOs, leftover debug), no regressions touching unrelated code. Reviewer must tag findings as `blocker`, `concern`, or `nit`.

2. **Dispatch Opus selective reviewer** in parallel with the bulk reviewers, ONLY when at least one of these warrants apply:
   - A chunk was tagged Opus-tier in Phase 4
   - Touched paths match correctness-critical patterns (auth, crypto, payments, transactions, migrations, concurrency primitives)
   - The spec called out correctness or security concerns
   - A chunk involved a novel algorithm or non-trivial state machine

   Use `subagent_type: general-purpose`, `model: opus`. The Opus reviewer's prompt scopes to ONLY the warranted subset (don't have it review trivial chunks).

3. **Consolidate findings** in the parent session:
   - Collect findings from all reviewers
   - Dedupe across reviewers (same blocker reported twice → one entry)
   - Sort: blockers first, concerns next, nits last
   - Group by chunk for re-dispatch clarity

4. **Auto-loop policy** (cap: 2 review iterations per execution batch):
   - **Blockers present** → for each affected chunk, refine its prompt with the reviewer feedback and re-dispatch via Phase 5's escalation rules (refine prompt → bump tier → surface). After re-dispatch completes, re-run Phase 6 review on the re-dispatched chunks ONLY (don't re-review clean chunks). Increment the iteration counter.
   - **Concerns only** → present to the user via `AskUserQuestion`:
     - **Address now** — convert each concern into a fix chunk and dispatch
     - **Defer** — record concerns for the hand-off summary and proceed
   - **Only nits or clean** → proceed to Phase 7
   - If iteration counter hits 2 with blockers still present, surface all remaining findings to the user with full context and stop the auto-loop.

### Phase 7 — Hand-off

Goal: summarize and route to the appropriate finalization flow.

1. **Produce a final summary** for the user covering:
   - One-line outcome of the feature
   - Files changed (grouped by chunk)
   - Test coverage added (if any)
   - Deferred concerns from Phase 6 (if any)
   - Any chunks surfaced for manual handling (if any)

2. **Offer hand-off** via `AskUserQuestion`:
   - **Ship it** — invoke `/git-tools:ship` to commit, push, open PR, watch CI
   - **End session** — invoke `/session:session-end` for the review-then-PR flow
   - **Pause here** — do nothing further; user will finalize manually

Do NOT auto-commit, push, or open a PR — always go through the user's choice in this final gate.

### Notes

- **Always think about whether the workflow is the right tool.** If the user invoked this for a small, well-scoped change, gently suggest `/session:session-start` instead before kicking off Phase 1.
- **Do not skip the user gates.** Phases 3 and 5 must use `AskUserQuestion`. The auto-loop in Phase 6 is the only place the workflow advances without an explicit gate.
- **Sub-agent prompts are self-contained.** Every `Agent` call's prompt must include enough context that the agent can succeed without seeing the parent conversation.
- **Parallel dispatch matters.** Within a Phase 1 angle set, a Phase 5 wave, or a Phase 6 reviewer batch, issue all `Agent` calls in a single message so they run concurrently.
