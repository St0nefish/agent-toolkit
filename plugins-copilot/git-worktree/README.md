# Git Worktree

Git worktree lifecycle management for parallel agentic work — create, list, and remove worktrees with auto-whitelisting and proactive context-mismatch detection.

> **Copilot CLI only.** Claude Code has built-in worktree management; this plugin is not listed in the Claude Code marketplace.

## Installation

Install from the Copilot CLI plugin marketplace:

```text
git-worktree plugin from St0nefish/agent-toolkit
```

## How It Works

Worktrees are created under `.github/worktrees/<branch-slug>` inside the repo root (auto-added to `.gitignore` on first use). Keeping them in-repo means the harness's working-directory permission scope already covers them — operations against worktree paths don't trigger per-path approval prompts.

A `preToolUse` hook (`worktree-whitelist.sh`) auto-allows:

1. All `git worktree` management commands (`add`, `remove`, `prune`, `move`, `lock`, `unlock`)
2. Bash commands that reference a registered worktree path
3. Edit/Write file operations targeting a registered worktree path

## Commands

| Command | Description |
|---------|-------------|
| `/worktree:create <branch>` | Create a new linked worktree on the given branch (creates the branch if it doesn't exist) |
| `/worktree:list` | List all active worktrees — path, branch, and working-tree status |
| `/worktree:remove <name>` | Remove a worktree by slug or path; optionally delete the branch |

### create options

```bash
# Create from the current HEAD
/worktree:create feature-auth

# Create from a specific base branch
/worktree:create feature-auth --from main
```

### remove options

Pass `--delete-branch` to also delete the branch (safe delete — fails if unmerged). Pass `--force` to remove a worktree that has uncommitted changes.

## Skill (Model-Triggered)

The `parallel-work` skill fires automatically when the model detects that the user's new request is unrelated to the current branch's uncommitted changes, or when the user explicitly asks for parallel/isolated work. It surfaces a worktree suggestion before starting the new work so the user can keep both contexts clean.

Trigger phrases include: "work on this in parallel", "without touching my current branch", "run tests in a clean checkout", "separate branch for this".

## Typical Workflow

```text
/worktree:create feature-auth     # creates .github/worktrees/feature-auth/
cd .github/worktrees/feature-auth
  ... implement feature-auth ...
/worktree:remove feature-auth     # prunes metadata; optionally deletes branch
```

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `git` | Yes | All worktree operations |
