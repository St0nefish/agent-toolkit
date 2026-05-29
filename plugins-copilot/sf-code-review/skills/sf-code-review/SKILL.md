---
user-invocable: false
name: sf-code-review
description: >-
  Use this skill for extensive code reviews of current changes when the user
  wants chunked, cross-family review with dual mid-range reviewers and targeted
  Opus adjudication. Trigger phrases include "extensive code review", "split
  the review into chunks", "dual review", "reconcile findings", and
  "stonefish code review".
allowed-tools: Bash, Read, AskUserQuestion, Task
---

# sf-code-review — chunked cross-family review

**Purpose.** Run a repeatable review pipeline over the current changeset: scope the
diff, collect review-specific focus items, split the work into coherent chunks,
review each chunk with two different mid-range models, and use a targeted Opus
pass only to adjudicate candidate findings before producing a triage-ready report.

If the user explicitly invokes `/sf-code-review:review`, use this exact procedure.

## When to use

Use this workflow when the user wants a deeper review than a single-pass code
review, especially when they ask for any of the following:

- "extensive code review"
- "split the review into chunks"
- "dual review"
- "two reviewers"
- "reconcile findings"
- "stonefish code review"

Do **not** use this workflow for tiny quick reviews where a normal single-pass
review is enough.

## Default review contract

1. **Baseline review always applies.** Even when the user supplies focus items,
   still check for correctness, regressions, interface/config/schema drift,
   test gaps, and obvious breakage.
2. **Custom focus areas add to the baseline.** They do not replace it.
3. **Exceptions are narrow.** Named exceptions only suppress explicit
   false-positive classes or intentional deviations. They never waive real
   correctness, auth, security, or data-loss concerns without evidence.
4. **Opus is an adjudicator, not a third reviewer.**
5. **Pin Opus cost.** When Opus is needed, use **only** `claude-opus-4.6`.
   Never substitute `claude-opus-4.7` or `claude-opus-4.8`.

## Procedure

### 0. Capture scope and review-specific inputs

Parse command arguments if present.

- If `--staged` is present, review `git diff --cached` and ignore `--base`.
- Else if `--base <ref>` is present, review `<ref>...HEAD`.
- Else default to the merge-base between `HEAD` and the default branch.
- If `--scope <path> ...` is present, restrict all diff commands to those paths.

If the user has not already provided review-specific focus items, ask via
`AskUserQuestion` for:

- focus items / architectural invariants
- optional named exceptions / known-safe churn
- optional path narrowing if the scope is too large

### 1. Gather one authoritative git snapshot

Use direct git commands as the source of truth:

```bash
git status --porcelain=v1 -b
default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||')
base=$(git merge-base HEAD "origin/$default")
git diff --stat "$base"...HEAD
git diff --name-only "$base"...HEAD
git diff --numstat "$base"...HEAD
```

For staged reviews, use the `--cached` equivalents instead. For path-scoped
reviews, append `-- <paths...>` to every diff command.

Capture:

- scope mode (`staged`, `base-ref`, or `default-merge-base`)
- base ref or merge-base
- changed files
- per-file diff size
- rough directory grouping

If the scoped diff is empty, report that there is nothing to review and stop.

### 2. Build the chunk plan

Chunk by **semantic unit first**, size second. Keep these together whenever
possible:

- implementation + touched interface / contract
- migration / config change + affected callers
- behavior change + tests

Rules:

- For small diffs (roughly `<= 3` files or `<= 250` changed lines), use a
  single chunk instead of forcing chunking.
- Prefer chunks of roughly `150-400` changed lines.
- Default to at most `6` chunks.
- If the review would exceed `6` chunks or roughly `2500` changed lines after
  scoping, show the chunk plan and ask the user whether to narrow the scope or
  review in phases before dispatching agents.

### 3. Run one diff-wide cross-cutting sweep

Run one whole-diff sweep before chunk-level adjudication. Its job is to look
for **cross-cutting concerns**, not to replace chunk review.

Prefer a `code-review` agent with model `gpt-5.4`. Only switch this sweep to
`general-purpose` with `gpt-5.4` if the user's focus items clearly require
reading surrounding unchanged code or architectural context.

The sweep must check this fixed checklist plus the user-provided focus items:

- interface / schema drift
- call-site mismatch across files
- auth / permission boundary changes
- transaction ordering / idempotency changes
- config or migration compatibility
- multi-file behavior changes lacking tests

Return cross-cutting concerns only. Do not use this pass as a second full review.

### 4. Run dual first-pass chunk reviews

For each chunk, launch **two** independent `code-review` agents in parallel:

- one with model `claude-sonnet-4.6`
- one with model `gpt-5.4`

Give both reviewers the same chunk scope and the same review contract:

- baseline review
- user focus items
- named exceptions
- chunk manifest and relevant diff context

Require each reviewer to return a **strict finding schema**. Free-form prose is
not acceptable.

If a reviewer finds nothing, it must return exactly:

```text
chunk_id: <chunk-id>
NO_FINDINGS
```

Otherwise require this structure for every finding:

```text
chunk_id: <chunk-id>
findings:
  - finding_id: <stable-id>
    file:line: <path:line or path>
    severity: critical|high|medium|low
    confidence: high|medium|low
    category: correctness|regression|architecture|security|performance|tests|compatibility
    claim: <one-sentence issue statement>
    why_it_matters: <impact>
    minimal_evidence: <smallest diff/context that supports the claim>
    suggested_check: <what to verify or change>
```

### 5. Dedupe and prepare candidate findings

Before invoking Opus:

- dedupe equivalent findings across the two reviewers
- keep disagreements where one reviewer flags an issue and the other does not
- keep findings that materially disagree on severity or scope
- discard noise that clearly does not meet the schema or lacks evidence

### 6. Run targeted Opus adjudication

Use `claude-opus-4.6` **only** as an adjudicator for candidate findings.

Hard rules:

- If no reviewer flags a candidate finding and there is no disagreement, skip Opus.
- Do not substitute `claude-opus-4.7` or `claude-opus-4.8`; keep Opus pinned to
  `claude-opus-4.6` for cost control.
- Batch candidate findings into as few targeted Opus passes as practical.
- Prefer `code-review` for adjudication when the candidate can be judged from
  the touched diff and nearby context.
- Use `general-purpose` with `claude-opus-4.6` only when a candidate cannot be
  resolved without broader surrounding code or architectural context.
- Never pass the full diff to Opus unless a candidate cannot be understood otherwise.
- Opus may only evaluate supplied candidate findings plus minimal supporting context.
- Opus must not introduce net-new unrelated findings.

Tell Opus explicitly: **you are an adjudicator, not a third reviewer**.

Require one verdict per candidate finding:

```text
finding_id: <stable-id>
verdict: confirmed|rejected|uncertain
severity: critical|high|medium|low
confidence: high|medium|low
reason: <why>
recommended_fix: <specific next step>
```

### 7. Consolidate the final report

Return a triage-ready report with these sections, in this order:

1. **Review metadata** — base, scope mode, focus items, exceptions, chunk count
2. **Overall risk** — a short paragraph on merge risk / likely breakage surface
3. **Confirmed issues** — severity, confidence, file:line, chunk, reviewers involved,
   why it matters, recommended fix
4. **Open questions / uncertain items**
5. **Cross-cutting concerns**
6. **Rejected findings** — short reason for rejection
7. **Counts** — candidate, confirmed, rejected, uncertain

## What not to do

- Do **not** let custom focus items replace the baseline review.
- Do **not** let named exceptions suppress broad categories of real risk.
- Do **not** turn the cross-cutting sweep into another full review.
- Do **not** let Opus search for new issues unrelated to supplied candidates.
- Do **not** automatically run one Opus pass per chunk when a smaller number of
  targeted adjudication batches will do.
