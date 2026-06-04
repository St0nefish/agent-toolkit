# git-worktree Copilot extension

Native GitHub Copilot CLI worktree tools for parallel checkout management.

## Repo-local usage

This repository ships the extension at `.github/extensions/git-worktree/`, so Copilot CLI discovers it automatically when you work inside this repo.

Available native tools:

- `sf_git_worktree_status`
- `sf_git_worktree_create`
- `sf_git_worktree_remove`
- `sf_git_worktree_suggest`

`onSessionStart` injects lightweight context about the current checkout, branch, and linked worktree count. A narrow `onUserPromptSubmitted` hook also adds a small nudge when the user explicitly asks for worktree/parallel/isolation flows, pointing the model at `sf_git_worktree_suggest` and `sf_git_worktree_create`.

## User-level install / update

Install or update the same extension for all repos with:

```bash
curl -fsSL https://raw.githubusercontent.com/St0nefish/agent-toolkit/master/scripts/install-copilot-git-worktree.sh | bash
```

The installer copies the extension into `~/.copilot/extensions/git-worktree` using this repo as the canonical source of truth. Project extensions still win on name collision, so this repo's local copy shadows the user-installed one here.

## Behavior

The extension keeps `git` as the source of truth. The JS layer provides tool registration, status normalization, suggestion logic, and session context. Create/remove flows reuse the shell scripts in `scripts/`.
