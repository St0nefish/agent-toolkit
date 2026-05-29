---
description: "Run a chunked multi-model code review with dual Sonnet/GPT reviewers and targeted Opus adjudication"
argument-hint: "[--base <ref>] [--staged] [--scope <path> ...] [--focus \"<item>; <item>\"] [--exception \"<false-positive class>; <false-positive class>\"]"
allowed-tools: Bash, Read, AskUserQuestion, Task
---

Run the Stonefish code-review workflow over the current changeset: scope the diff,
collect review-specific focus items, split the review into coherent chunks, dual-review
each chunk with Claude Sonnet 4.6 and GPT-5.4, use Claude Opus 4.6 only to adjudicate
candidate findings, then consolidate a triage-ready report.

This command invokes the `sf-code-review` skill — use that skill's full procedure.

## Argument handling

- `--staged` — review the staged snapshot with `git diff --cached`; if present, ignore `--base`
- `--base <ref>` — review `<ref>...HEAD`
- `--scope <path> ...` — restrict review to one or more paths
- `--focus "A; B; C"` — add review-specific priorities or architectural invariants
- `--exception "A; B"` — name specific false-positive classes or intentional deviations

If `$ARGUMENTS` contains freeform text beyond these flags, preserve it as additional
review context instead of dropping it.

## Rules

1. Custom focus areas add to the baseline review; they do not replace correctness,
   compatibility, regression, or testing checks.
2. Opus is an adjudicator, not a third reviewer.
3. If no reviewer flags a candidate issue and there is no disagreement, skip Opus.
4. Never pass the full diff to Opus unless a candidate cannot be understood otherwise.
5. Prefer batching candidate findings into as few targeted Opus passes as practical.
6. When Opus is needed, use **only** `claude-opus-4.6` — never `claude-opus-4.7` or `claude-opus-4.8`.
