---
disable-model-invocation: true
name: session-end
description: "Wrap up the session: update docs, finish loose ends, review (unless already done) + fix, sweep issues, then ship"
allowed-tools: Bash, Read, Edit, Write, Skill, Agent, AskUserQuestion, ExitWorktree
---

Close out the session's work, then hand off to `/git-tools:ship` for the
commit → PR → CI → merge → cleanup lifecycle. This skill owns only the
pre-ship quality pass; `ship` owns everything git/PR/worktree.

**Preflight:** this skill hands off to `git-tools:ship`. If that skill is not
available (the `git-tools` plugin is not installed or enabled), say so and stop
before doing any docs or review work. The `code-review` skill is optional: step 3
falls back to a review agent when it is missing.

Work from what you already know about this session. **Do not** start by running
a pile of `git diff` / log commands to rediscover it. One cheap orientation is
enough:

```bash
git status --short -b
```

If the tree is clean and the branch has nothing ahead of the default branch,
say there is nothing to finalize and stop.

### 1. Docs

Update every doc the work made stale: README, CLAUDE.md, docs/, changelogs,
help text, comments, and version fields where the repo requires a bump. Edit
what is wrong; do not write new docs nobody asked for.

### 2. Finish adjacent work

Complete anything this change obviously implies and left dangling: tests for
new behavior, call sites or mirrors that need the same change, leftover TODOs
or debug code you added, temp files. Stay in scope — note unrelated problems
instead of fixing them. Do not run repo validation here; step 3 runs it once.

### 3. Review and fix (hard gate)

Shipping requires a review of the current state of the work. First decide whether
one already happened **in this session**: a `code-review ... --fix` run (or an
equivalent review-and-fix agent) earlier in the conversation, with no code edits
since other than that review's own fixes. Steps 1-2 edits to docs count as
non-code; any code or test edit made after the review means it is stale.

- **Already reviewed and still current** — skip the review and say so in one
  line (for example "Review already ran this session; skipping").
- **Otherwise** — invoke the `code-review` skill with `--fix` on the working
  tree. If the `code-review` skill is not available, use the Agent tool to spawn
  a general-purpose review-and-fix agent over the working-tree diff instead: it
  reports findings (correctness bugs, edge cases, error handling, missing tests,
  with file:line) and applies the fixes. Either way, apply the findings, then run
  the repo's documented validation **once** (for example `validate-all.sh` or the
  test command in CLAUDE.md) and fix what fails. Surface only findings you chose
  not to fix, with a one-line reason each.

This is a hard gate: never invoke `ship` while a required review is outstanding,
and do not offer the user a way to skip it. Skip only if the user explicitly
tells you to.

### 4. Issue sweep

Decide which issues this work resolves.

1. Collect candidates. Start with the issue(s) linked to this session (prior
   context or an explicit `#N` — never parse it from the branch name) and fetch
   just those (`gh issue view N --json number,title,body,state` or
   `tea issues N --output json`; `git-wait platform` reports which). List other
   open issues only when their titles could plausibly overlap this work, and keep
   the list small:

   ```bash
   gh issue list --state open --limit 20 --json number,title
   ```

   Use `tea issues list --limit 20` on Gitea. With no linked issue, this list is
   the only source.
2. Classify each as **resolved** (the diff fully addresses it), **partial**
   (progress but not done), or **unrelated**. Read an issue body only when the
   title is ambiguous.
3. Resolved → will be closed via the PR. Partial → leave open and write down the list of partial issue numbers
   now (with a one-line note of the progress made on each), so it survives the
   ship step; the comment is posted in step 6 after the merge. If the call is
   genuinely unclear, ask once via `AskUserQuestion`, batched across all unclear
   issues.
4. If something should be pushed through to completion and is small, finish it
   now with **one** extra pass (steps 2-3 once more, no further loop) rather than
   leaving it open; anything still unfinished stays open as partial.

Also list any new problems found along the way that deserve their own issue;
offer to file them, do not file without a yes.

### 5. Ship

Only once step 3 is satisfied, invoke `git-tools:ship` via the `Skill` tool. Pass as arguments the closing
lines the PR body must contain — `Fixes #N` for bugs, `Closes #N` otherwise,
one per resolved issue — and tell it the PR body should summarize the review
and docs changes. `ship` handles staging, branch, push, PR, CI, merge wait,
post-merge run, return to the default branch, and worktree teardown.

### 6. Comment on partial issues

Only after ship reports the PR merged, post a short comment on each partial issue
recorded in step 4, referencing the merged PR (number or URL) and what remains:

```bash
gh issue comment N --body "Progress in PR #P (merged): <what was done>. Remaining: <what is left>."
```

Use `tea comment N "<same text>"` on Gitea. If the PR did not merge (closed,
blocked, timed out), do not comment; say so in the report instead. Skip this
step when there are no partial issues.

### 7. Report

After `ship` finishes and partial-issue comments are posted, give a short summary:
PR URL and merge/CI state, issues closed, partial issues commented (only those
actually commented), and anything skipped or left for the user.

If this session was entered with `EnterWorktree` and the worktree directory no
longer exists after `ship` (ship removes it with plain git), call `ExitWorktree`
with `action: "keep"` to reset the harness's session state. Never use `remove`
or `discard` here; `ship` already removed the directory.
