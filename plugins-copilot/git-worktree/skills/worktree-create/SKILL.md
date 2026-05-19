---
name: worktree-create
description: >-
  Create a new linked git worktree on its own branch under
  `.github/worktrees/<branch-slug>` for parallel agentic work. Trigger when
  the user says "create a worktree", "new worktree for X", "make a worktree
  on branch Y", "spin up a parallel checkout", or "/worktree-create".
  Supports an optional base branch via `--from <branch>`.
allowed-tools: shell
---

Create a new linked git worktree. Keeping worktrees inside the repo
(`.github/worktrees/`, auto-gitignored on first use) keeps operations
against them inside the session's CWD scope.

## Steps

1. Use direct `git worktree` commands rather than plugin helper-script paths;
   the plugin-root environment variable is not guaranteed to exist inside Bash
   tool invocations.

2. Resolve the repo root with `git rev-parse --show-toplevel`, then set the
   base directory to `${WORKTREE_BASE_DIR:-<repo-root>/.github/worktrees}`.
   On first use, create the directory and ensure it is gitignored (skip the
   gitignore step if `WORKTREE_BASE_DIR` is overridden).

3. Convert the requested branch name into a directory slug by:
   - replacing `/` with `-`
   - replacing remaining non-`[A-Za-z0-9._-]` characters with `-`
   - collapsing repeated `-`
   - trimming leading and trailing `-`

4. Set the worktree path to `<base-dir>/<slug>` and stop with a clear error
   if that directory already exists.

5. If the branch already exists locally, run `git worktree add <path> <branch>`.
   Otherwise create it with `git worktree add <path> -b <branch> [<base-branch>]`,
   defaulting the base branch to the current branch when the user did not specify one.

6. Report the worktree path and branch back to the user.

7. Remind them to run `/worktree-remove <name>` when finished.

## Notes

- If the branch already exists, the worktree checks it out without creating
  a new one.
- The base directory (`.github/worktrees/`) is created automatically and
  added to `.gitignore` on first use.
- Override the base directory with `WORKTREE_BASE_DIR` (skips the
  auto-gitignore step).
