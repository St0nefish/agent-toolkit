# git-worktree Copilot extension

Native GitHub Copilot CLI worktree tools for parallel checkout management.

## Canonical source

This repository keeps the canonical source at `copilot-extensions/git-worktree/`, outside Copilot CLI's project auto-discovery path. That keeps the extension **user-level only** instead of loading a second project-scoped copy when you work inside this repo.

Available native tools:

- `sf_git_worktree_status`
- `sf_git_worktree_create`
- `sf_git_worktree_remove`
- `sf_git_worktree_suggest`

The extension keeps a narrow `onPreToolUse` hook that auto-allows its own `sf_git_worktree_*` tools so Copilot does not stop to prompt on each one individually.

## User-level install / update

Install or update the same extension for all repos with:

```bash
curl -fsSL https://raw.githubusercontent.com/St0nefish/agent-toolkit/master/scripts/install-copilot-git-worktree.sh | bash
```

The installer copies the extension into `~/.copilot/extensions/git-worktree`, installs a helper command at `~/.local/bin/copilot-git-worktree-allow`, and seeds `~/.copilot/permissions-config.json` for the current repo (git root when available, otherwise the current directory). That persists:

- `extension-permission-access` for `user:git-worktree`
- `custom-tool` approvals for `sf_git_worktree_status`, `sf_git_worktree_create`, `sf_git_worktree_remove`, and `sf_git_worktree_suggest`

For any future repo, run this from inside that repo:

```bash
copilot-git-worktree-allow
```

Or target a specific repo path directly:

```bash
copilot-git-worktree-allow /path/to/repo
```

## Behavior

The extension keeps `git` as the source of truth. The JS layer provides tool registration, status normalization, suggestion logic, and session context. Create/remove flows reuse the shell scripts in `scripts/`.
