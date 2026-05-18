# Git Worktree

Git worktree lifecycle management for parallel agentic work in GitHub Copilot CLI — create, list, and remove worktrees with auto-whitelisting and proactive context-mismatch detection.

> **Copilot CLI only.** Copilot CLI has no built-in worktree management; this plugin fills that gap.

## Installation

Install from the Copilot CLI plugin marketplace:

```text
git-worktree plugin from St0nefish/agent-toolkit
```

## How It Works

Worktrees are created under `.github/worktrees/<branch-slug>` inside the repo root (auto-added to `.gitignore` on first use). Keeping them in-repo means operations against worktree paths stay inside the session's working-directory scope.

A `preToolUse` hook (`worktree-whitelist.sh`) auto-allows:

1. All `git worktree` management commands (`add`, `remove`, `prune`, `move`, `lock`, `unlock`)
2. Bash commands that reference a registered worktree path
3. Edit/Write file operations targeting a registered worktree path

## Skills

All operations are exposed as skills — the model can invoke them automatically when triggered by your phrasing, and you can call them explicitly via slash:

| Skill | Slash form | Trigger phrases |
|-------|------------|-----------------|
| `worktree-list` | `/worktree-list` | "list worktrees", "show worktrees", "what worktrees do I have" |
| `worktree-create` | `/worktree-create <branch>` | "create a worktree", "new worktree for X", "spin up a parallel checkout" |
| `worktree-remove` | `/worktree-remove <name>` | "remove worktree", "delete worktree X", "clean up the worktree" |
| `worktree-parallel-work` | (auto) | "in parallel", "without touching my current branch", "isolated checkout" |

### `worktree-create` options

```bash
# Create from the current HEAD
/worktree-create feature-auth

# Create from a specific base branch
/worktree-create feature-auth --from main
```

### `worktree-remove` options

Pass `--delete-branch` to also delete the branch (safe delete — fails if unmerged). Pass `--force` to remove a worktree that has uncommitted changes.

### `worktree-parallel-work` (auto-triggered)

Fires when the model detects that a new request is unrelated to existing uncommitted changes on the current branch, or when you explicitly ask for parallel/isolated work. It surfaces the worktree suggestion before starting the new work so both contexts stay clean.

## Typical Workflow

```text
/worktree-create feature-auth     # creates .github/worktrees/feature-auth/
cd .github/worktrees/feature-auth
  ... implement feature-auth ...
/worktree-remove feature-auth     # prunes metadata; optionally deletes branch
```

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `git` | Yes | All worktree operations |

## Troubleshooting

### "Allow directory access" prompts when running plugin scripts

Copilot CLI does not auto-trust plugin install directories — every time the plugin runs a script under `~/.copilot/installed-plugins/agent-toolkit/git-worktree/scripts/`, the path validator prompts for approval. This is a Copilot-CLI-wide behavior, not specific to this plugin.

To silence the prompt once and for all, add the plugin install dir to your trusted folders:

```text
/add-dir ~/.copilot/installed-plugins/agent-toolkit/git-worktree
```

Or launch the CLI with `--allow-all-paths` for one-off sessions.
