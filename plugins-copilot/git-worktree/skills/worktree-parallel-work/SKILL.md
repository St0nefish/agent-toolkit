---
name: worktree-parallel-work
description: >-
  Suggest a git worktree when the user wants parallel/isolated work, asks to
  keep the current branch untouched, or when the new request is clearly
  unrelated to existing uncommitted changes on the current branch. Trigger
  phrases: "in parallel", "simultaneously", "without touching my current
  branch", "run tests in a clean checkout", "isolated environment",
  "separate branch for this", "background task".
allowed-tools: shell
---

When the user wants to work on something in parallel, in isolation, or
without disturbing the current branch — or when the new request is clearly
unrelated to in-progress uncommitted changes — propose a git worktree. A
worktree gives a second fully-functional checkout under
`.github/worktrees/<slug>` (auto-gitignored): no stashing, no branch
switching, no context loss.

## When to trigger

**Explicit signals**: the user says "in parallel", "without touching my
current branch", "run tests in a clean checkout", "background task",
"separate branch for this", or similar.

**Implicit context mismatch**: ALL of the following hold:

1. `git status --short` shows uncommitted/staged changes, AND
2. The new request is clearly unrelated (different feature area, different
   issue, hotfix on top of in-progress work), AND
3. Completing the new request would interleave unrelated changes into the
   same branch.

In implicit cases, pause and surface the worktree suggestion first.

## Response

1. One-sentence observation: "I see uncommitted changes on this branch
   related to X — your new request looks unrelated."

2. Offer to create the worktree using the direct `git worktree add` flow
   described by the worktree-create skill: derive the worktree base
   directory from the repo root, slug the suggested branch name, and
   create the worktree without relying on plugin-root environment
   variables inside Bash.

3. Once created, run commands in the worktree via `cd <path> && ...`.

4. After the work is done, suggest cleanup: remove the worktree with the
   same direct `git worktree remove` flow described by the worktree-remove
   skill, and optionally delete the branch with `git branch -d`.

## Rules

- Skip if the user is already in a worktree (`git worktree list` shows >1).
- Skip trivial single-step or read-only tasks.
- Don't silently start unrelated work on the current branch — surface the
  suggestion first.
