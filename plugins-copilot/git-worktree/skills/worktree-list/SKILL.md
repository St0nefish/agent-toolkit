---
name: worktree-list
description: >-
  List all active git worktrees for the current repository, including path,
  branch, and working-tree status. Trigger when the user asks "list worktrees",
  "show worktrees", "what worktrees do I have", or wants to see active
  parallel checkouts before creating or removing one.
allowed-tools: shell
---

Use direct `git worktree` commands rather than plugin helper-script paths;
the plugin-root environment variable is not guaranteed to exist inside Bash
tool invocations.

## Steps

1. Run `git worktree list --porcelain` and parse the records into PATH,
   BRANCH, and STATUS columns:
   - PATH — the worktree directory
   - BRANCH — the checked-out branch (mark detached HEAD as `(detached)`)
   - STATUS — `clean` when the worktree has no uncommitted/staged changes,
     or a short marker otherwise (e.g. `dirty`)

2. Present the table verbatim to the user.

3. If only the main worktree is listed, suggest `/worktree-create <branch-name>`
   to create one.
