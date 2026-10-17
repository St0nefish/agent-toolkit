---
name: session-end
description: "Use when the user signals the session's work is complete and ready to land (wrap up, close out, finalize, ready for a PR): loads the full end checklist — docs, review, issue sweep so resolved issues get closed, then ship. Not for mid-task 'done'/'finish'."
allowed-tools: Bash, Read, Edit, Write, Skill, Agent, AskUserQuestion, ExitWorktree
---

Close out the session's work, then hand off to `/git-tools:ship` for the
commit → PR → CI → merge → cleanup lifecycle. This skill owns only the
pre-ship quality pass; `ship` owns everything git/PR/worktree. This is where the
last (or only) unit of the scope gets shipped, exactly once; earlier units were
already landed via `ship`. Run straight
through steps 1-4 with no routine prompts; the one deliberate stop is step 5,
**before** anything is shipped: summarize the work and caveats and wait for the
user's go. Only after that go do steps 6-8 run (ship, CI, re-merge if needed,
cleanup, final summary) without stopping again.

**Preflight:** this skill hands off to `git-tools:ship`. If that skill is not
available (the `git-tools` plugin is not installed or enabled), say so and stop
before doing any docs or review work. The `code-review` skill is optional: step 3
falls back to a review agent when it is missing.

Then, before any docs or review work, detect the platform:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
```

If it fails, stop and tell the user, or offer to proceed locally without the
issue and PR steps (skip steps 4, 6 and 7 and do not invoke `ship`); in that mode step 5 offers only
**Done** and **Make changes first**, leaves the issue lines out of the summary, and
step 8 reports the local state instead of a PR. On success, capture
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
one already happened **in this session** and is still current:

- **Already reviewed and still current** — a review-and-fix run earlier in the
  conversation, followed by no code or test edits other than that review's own
  *minor* fixes. Docs edits from steps 1-2 count as non-code. Skip the review and
  say so in one line (for example "Review already ran this session; skipping").
- **Stale** — any code or test edit since the review, or review fixes that were
  *significant*: they changed logic or behavior, added or removed more than a few
  lines, or touched files outside the reviewed diff. Typos, wording, formatting,
  and comment tweaks are minor and do not make a review stale.

Otherwise run the loop below.

**Scale the effort to the change.** Pick the review level from the diff's size and
risk, not a fixed default: prose, docs, or config only, or a few lines in one
file → `low`; a handful of files with simple logic → `medium`; multi-file logic or
behavior changes → `high`; large, cross-cutting, or security-sensitive changes
(auth, hooks, shared utils, anything hard to reverse) → `xhigh`.

**Review → triage → fix, at most three passes:**

1. **Review.** Invoke the `code-review` skill at that level **without** `--fix`,
   so findings come back unapplied. If the `code-review` skill is not available,
   use the Agent tool to spawn a general-purpose review agent over the
   working-tree diff: it reports findings (correctness bugs, edge cases, error
   handling, missing tests, with file:line) and changes nothing.
2. **Triage.** Do not fix findings on the reviewer's word alone. Spawn one triage
   `Agent` with a model matched to the change: `haiku` for trivial diffs,
   `sonnet` for ordinary ones, `opus` for complex or security-sensitive ones. Give
   it the findings and the diff and ask, per finding, whether it is **real** (a
   defect that can actually occur) and **significant** (worth fixing in this PR),
   with a one-line reason. Findings judged not real, or real but minor, are
   dropped and reported with that reason. They never trigger another pass.
3. **Fix.** Apply the real, significant findings, then run the repo's documented
   validation **once** (for example `validate-all.sh` or the test command in
   CLAUDE.md) and fix what fails.
4. **Decide whether to loop.** If the fixes were significant (see "Stale" above)
   and this was not pass 3, run another pass from step 1; otherwise the review is
   satisfied.

Pass 3 is the last pass; do not re-review after its fixes. If pass 3 produced
significant fixes, real significant findings remain, or validation still fails,
**stop**: do not invoke `ship`. Ask the user via `AskUserQuestion`, listing what
remains with a one-line reason each, and let them choose whether to ship as is or
direct changes. Never start a fourth pass on your own.

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
   ship step; the comment is posted in step 7 after the merge. If the call is
   genuinely unclear, ask once via `AskUserQuestion`, batched across all unclear
   issues.
4. If something should be pushed through to completion and is small, finish it
   now with **one** extra pass (steps 2-3 once more, no further loop) rather than
   leaving it open; anything still unfinished stays open as partial.

Also list any new problems found along the way that deserve their own issue;
carry them to the step 5 summary rather than filing them unprompted.

### 5. Summarize and wait for the user's go (STOP)

Nothing has been committed, pushed, or opened as a PR yet. Build the summary, then
**stop and wait for the user's reply** with `AskUserQuestion` (not a plain-text
question), so the user can answer from `/rc` on their phone. Print the full summary
as text first, and put a condensed version (outcome, validation, top caveats) in
the question text itself, because the remote client may not show the text above it.
Ask one question with these options: **Ship it** (recommended) and **Make changes
first**; the user's own words, including a cancel, arrive through "Other". The
summary covers:

- One-line outcome and the branch.
- What changed, per file (or per area for a large diff), including the docs edits.
- Validation status (what ran and passed; say plainly if something was not run)
  and the review outcome: findings fixed, and any you chose not to fix with the
  reason.
- **Caveats** — known or potential problems, assumptions, and uncovered edge
  cases, stated specifically. Omit only if there are genuinely none.
- Issues this work will close, partial issues, and proposed new issues.

If the user cancels or says to keep the work local, stop: do not invoke `ship`,
and report the branch and working-tree state. If they pick **Make changes first**
without saying what to change, ask. If they pick it or answer with changes, make them,
re-run validation once, redo the step 3 review if the edits made it stale, and ask
again with a fresh summary. Do not invoke `ship`, commit, push, or open a PR until
the user picks **Ship it** for the current state of the work; an earlier approval
(for example of the plan) does not count.

### 6. Ship

Only once the user has given the go in step 5, and step 3 is satisfied, invoke
`git-tools:ship` via the `Skill` tool. Pass as arguments the closing
lines the PR body must contain — `Fixes #N` for bugs, `Closes #N` otherwise,
one per resolved issue — and tell it the PR body should summarize the review
and docs changes. `ship` handles staging, branch, push, PR, CI, merge wait,
post-merge run, return to the default branch, and worktree teardown.

The user's go covers the whole lifecycle: watch CI, fix forward a failure clearly
caused by this change and re-merge (`ship` caps this at two attempts), and clean
up. Do not ask again between those steps. If `ship` still stops on a CI failure
or a blocked merge, stop too: report the state and do not comment on any issue.
Distinguish "merged" from "auto-merge enabled but not yet merged": post no
"resolved" or progress comment until the PR is actually merged. Offer to wait for
the merge, or tell the user to re-run the sweep (step 7) once it lands.

### 7. Comment on partial issues

`ship` step 9 removes the worktree, so the current directory may no longer
exist. Before running any command here, if it is gone, call `ExitWorktree` with
`action: "keep"` (see step 8), or switch to a valid directory such as the main
checkout. Always use the `-R owner/repo` / `--repo` form captured in preflight.

Only after ship reports the PR merged, post a short comment on each partial issue
recorded in step 4, referencing the merged PR (number or URL) and what remains:

```bash
gh -R owner/repo issue comment N --body "Progress in PR #P (merged): <what was done>. Remaining: <what is left>."
```

Use `tea comment --repo owner/repo N "<same text>"` on Gitea. If the PR did not
merge (closed, blocked, timed out, or auto-merge pending), do not comment; say
so in the report instead. Skip this step when there are no partial issues.

### 8. Final report

After `ship` finishes and partial-issue comments are posted, give a short summary
of the final state: PR URL and merge/CI state (including any fix-forward commits
or re-merges), issues closed, partial issues commented (only those actually
commented), cleanup / worktree teardown done, and anything skipped or left for
the user. List the proposed new issues from step 4 and file them only if the user
asks. This is a report, not a further confirmation stop.

If this session was entered with `EnterWorktree` and the worktree directory no
longer exists after `ship` (ship removes it with plain git), call `ExitWorktree`
with `action: "keep"` to reset the harness's session state (do this at the start
of step 7 when that step has work to do). Never use `remove`
or `discard` here; `ship` already removed the directory.
