---
name: worktree-remove
description: >-
  Remove a linked git worktree when parallel work is complete. Trigger when
  the user says "remove worktree", "delete worktree X", "clean up the
  worktree", "/worktree-remove", or finishes a feature and wants to tear
  down the parallel checkout. Optional `--delete-branch` also drops the
  branch; `--force` removes worktrees with uncommitted changes.
allowed-tools: shell
---

Remove a linked git worktree. Optionally delete its branch. Use direct
`git worktree` commands rather than plugin helper-script paths; the
plugin-root environment variable is not guaranteed to exist inside Bash
tool invocations.

## Steps

1. Identify the target. The user can pass:
   - A slug name (e.g. `feature-auth`) — resolved against the entries in
     `git worktree list --porcelain` (match the leaf directory under
     `${WORKTREE_BASE_DIR:-<repo-root>/.github/worktrees}`)
   - An absolute path to the worktree directory

2. Check for uncommitted changes by inspecting the matching record from
   `git worktree list --porcelain`. If the worktree is dirty and the user
   did not request `--force`, refuse and explain.

3. Remove the worktree with `git worktree remove <path>`. Pass `--force`
   when the user explicitly requested it for a dirty worktree.

4. If the user passed `--delete-branch`, run `git branch -d <branch>` after
   removal. Use `git branch -D <branch>` only when the user explicitly
   confirms a force-delete (branch unmerged).

5. Run `git worktree prune` to clean up stale administrative state.

6. Confirm removal to the user.

## Notes

- `--delete-branch` uses `git branch -d` (safe delete — fails if unmerged).
  Tell the user if the branch wasn't deleted and how to force-delete.
- `git worktree prune` runs automatically after removal.
