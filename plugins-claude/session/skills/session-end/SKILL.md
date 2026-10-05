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

Then, before any docs or review work, detect the platform:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
```

If it fails, stop and tell the user, or offer to proceed locally without the
issue and PR steps (skip steps 4-6 and do not invoke `ship`). On success, capture
the `owner/repo` and the platform now (for example
`gh repo view --json nameWithOwner -q .nameWithOwner`, or parse
`git remote get-url origin`). Use `gh -R owner/repo` / `tea --repo owner/repo`
for every later issue command so they still work after `ship` removes the
worktree.

Work from what you already know about this session. **Do not** start by running
a pile of `git diff` / log commands to rediscover it. One cheap orientation is
enough. Determine the default branch (`git symbolic-ref --short
refs/remotes/origin/HEAD`, falling back to `main`, then `master`) and run:

```bash
git status --short -b
git rev-list --count <default>..HEAD
```

If the working tree is clean and the count is `0`, say there is nothing to
finalize and stop. Do not rely on the "ahead" count from `git status -b`: a
never-pushed branch has no upstream and shows none.

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
  test command in CLAUDE.md) and fix what fails. Cap this fix loop at two
  attempts: if validation or review findings still fail after the second, stop,
  report what remains, and do not invoke `ship`. Surface only findings you chose
  not to fix, with a one-line reason each.

This is a hard gate: never invoke `ship` while a required review is outstanding,
and do not offer the user a way to skip it. Skip only if the user explicitly
tells you to.

### 4. Issue sweep

Decide which issues this work resolves.

1. Collect candidates. Find the issue(s) linked to this session, in this order
   (never parse them from the branch name):
   1. `git config --get branch.<branch>.session-issues` — comma-separated
      closing lines such as `Closes #12,Fixes #13`; split on commas.
   2. Issues already known in this conversation's context.
   3. Explicit `#N` references in the skill arguments.
   4. Otherwise ask the user via `AskUserQuestion` which issues this work
      resolves (none is a valid answer).

   Fetch just those (`gh -R owner/repo issue view N --json
   number,title,body,state` or `tea issues N --repo owner/repo --output json`).
   Optionally list open issues (`gh -R owner/repo issue list --state open
   --limit 20 --json number,title`; `tea issues list --repo owner/repo --limit
   20` on Gitea) to **suggest** title-overlap candidates; treat these only as
   suggestions that need the user's confirmation, never as the silent primary
   path.
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

If `ship` stops on a CI failure or a blocked merge, stop too: report the state
and do not comment on any issue. Distinguish "merged" from "auto-merge enabled
but not yet merged": post no "resolved" or progress comment until the PR is
actually merged. Offer to wait for the merge, or tell the user to re-run the
sweep (step 6) once it lands.

### 6. Comment on partial issues

`ship` step 9 removes the worktree, so the current directory may no longer
exist. Before running any command here, if it is gone, call `ExitWorktree` with
`action: "keep"` (see step 7), or switch to a valid directory such as the main
checkout. Always use the `-R owner/repo` / `--repo` form captured in preflight.

Only after ship reports the PR merged, post a short comment on each partial issue
recorded in step 4, referencing the merged PR (number or URL) and what remains:

```bash
gh -R owner/repo issue comment N --body "Progress in PR #P (merged): <what was done>. Remaining: <what is left>."
```

Use `tea comment --repo owner/repo N "<same text>"` on Gitea. If the PR did not
merge (closed, blocked, timed out, or auto-merge pending), do not comment; say
so in the report instead. Skip this step when there are no partial issues.

### 7. Report

After `ship` finishes and partial-issue comments are posted, give a short summary:
PR URL and merge/CI state, issues closed, partial issues commented (only those
actually commented), and anything skipped or left for the user.

If this session was entered with `EnterWorktree` and the worktree directory no
longer exists after `ship` (ship removes it with plain git), call `ExitWorktree`
with `action: "keep"` to reset the harness's session state (do this at the start
of step 6 when that step has work to do). Never use `remove`
or `discard` here; `ship` already removed the directory.
