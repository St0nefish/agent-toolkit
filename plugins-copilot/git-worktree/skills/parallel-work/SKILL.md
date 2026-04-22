---
name: parallel-work
user-invocable: false
description: >-
  Suggest using a git worktree when the user requests parallel tasks, working
  on multiple features simultaneously, running tests in an isolated checkout,
  or doing background work without disturbing the current branch.
allowed-tools: Bash
---

When the user wants to work on something in parallel, in isolation, or without
touching the current branch, a git worktree is the right tool. A worktree gives
a second fully-functional checkout of the repo in a sibling directory —
no stashing, no branch switching, no context loss.

## When to trigger

Trigger proactively (without being asked) when the user says things like:

- "work on this in parallel", "do both at once", "simultaneously"
- "without touching my current branch", "keep my current work"
- "run tests in a clean checkout", "isolated environment"
- "background task", "separate branch for this"
- "while I continue working on X, also do Y"

## Response

1. Briefly explain what a git worktree provides in this context (1-2 sentences).

2. Offer to create one immediately:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-create.sh <suggested-branch-name>
   ```

   Suggest a branch name based on the task being discussed.

3. Explain that once created, you can run commands in the worktree by prefixing
   with `cd <path> && ...` — the worktree plugin's hook auto-approves operations
   targeting that directory.

4. After the work is done, remind the user to clean up:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/worktree-remove.sh <name> --delete-branch
   ```

## Rules

- Do NOT invoke this skill if the user is already working in a worktree (check `git worktree list`).
- Do NOT suggest worktrees for trivial single-step tasks — only when genuine parallelism or isolation is needed.
- Keep the explanation brief — the user likely just wants to get started.
