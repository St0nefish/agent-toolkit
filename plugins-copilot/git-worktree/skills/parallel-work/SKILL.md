---
name: parallel-work
user-invocable: false
description: >-
  Suggest using a git worktree when the user requests parallel tasks, working
  on multiple features simultaneously, running tests in an isolated checkout,
  doing background work without disturbing the current branch, or when the
  agent detects that the requested changes are unrelated to the current branch
  work (e.g., significant uncommitted changes exist on an unrelated topic).
allowed-tools: Bash
---

When the user wants to work on something in parallel, in isolation, or without
touching the current branch — or when the agent detects a context mismatch
between the current branch and the new request — a git worktree is the right
tool. A worktree gives a second fully-functional checkout under
`.github/worktrees/<slug>` inside the repo (auto-gitignored): no stashing, no
branch switching, no context loss, and no per-path permission prompts because
the path is covered by the harness's working-directory scope.

## When to trigger

### Explicit — user signals parallel or isolated work

Trigger proactively when the user says things like:

- "work on this in parallel", "do both at once", "simultaneously"
- "without touching my current branch", "keep my current work"
- "run tests in a clean checkout", "isolated environment"
- "background task", "separate branch for this"
- "while I continue working on X, also do Y"

### Implicit — agent detects an unrelated context

Trigger proactively when you observe ALL of the following:

1. There are uncommitted or staged changes on the current branch (check with
   `git status --short`), AND
2. The user's new request is clearly unrelated to those existing changes —
   different feature area, different file set, different issue, or a hotfix
   on top of in-progress work, AND
3. Completing the new request would interleave unrelated changes into the
   same branch/commit history.

**Examples of unrelated-context detection**:

- Current branch has uncommitted UI changes; user asks to fix an unrelated API bug.
- Current branch is mid-refactor of module A; user asks to add a new feature to module B.
- Current branch has half-done feature work; user asks to apply an urgent hotfix.
- Current branch name suggests one issue (e.g. `feature/auth`); user asks to
  work on something that belongs on a different issue entirely.

In these cases, pause and ask the user whether they'd like a worktree before
proceeding. **Do not silently start the new work on the current branch.**

## Checking for context mismatch

Before starting any significant new task, you may run:

```bash
git status --short
git --no-pager log --oneline -1
git --no-pager branch --show-current
```

If there are uncommitted changes and the new request is clearly unrelated,
raise the worktree suggestion.

## Response

1. Briefly describe what you noticed (1 sentence): e.g., "I see uncommitted
   changes related to X on this branch — your new request looks unrelated."

2. Ask if they want a worktree, or offer to create one directly:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <suggested-branch-name>
   ```

   Suggest a branch name based on the new task being discussed.

3. Explain that once created, commands run in the worktree via `cd <path> && ...`
   — the worktree plugin's hook auto-approves operations targeting that directory.

4. After the work is done, remind the user to clean up:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <name> --delete-branch
   ```

## Rules

- Do NOT invoke this skill if the user is already working in a worktree
  (`git worktree list` shows more than one entry).
- Do NOT suggest worktrees for trivial single-step tasks or read-only queries.
- Do NOT silently start unrelated work on the current branch — always surface
  the suggestion first and let the user decide.
- Keep the explanation brief — the user just wants to get started.
