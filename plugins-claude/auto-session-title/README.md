# auto-session-title

Auto-rename Claude Code sessions (and terminal tab titles) from git context. Claude Code mirrors the session title out to the terminal window/tab title, so one hook covers both surfaces.

## Behavior

A `UserPromptSubmit` hook fires on every user message and resolves a title like this:

| State | Emitted title |
|-------|---------------|
| Not in a git repo | nothing (Claude Code leaves the current title alone) |
| Detached HEAD, no override | nothing |
| Named branch, no override | `<repo>:<branch>` |
| Override file present | `<repo>:<override-line-1>` |
| Inside a worktree under `<repo>/.claude/worktrees/` or `<repo>/.github/worktrees/` | `<main-repo>↪<short-branch>` (or `<main-repo>↪<override>`) |

The project prefix is **always** preserved — the override file contains only the suffix.

## Worktrees

Agent-spawned worktrees (Claude Code's `EnterWorktree`, the `git-worktree` Copilot extension, etc.) often have long auto-generated paths and branch names like `agent-<bighash>` / `worktree-agent-<bighash>`. Naively combining the worktree directory with the branch produced unreadable titles like `agent-<bighash>:worktree-agent-<bighash>`.

When the checkout lives under either of the known worktree base directories, the hook now:

- Uses the **main repo** name (not the worktree directory) as the prefix.
- Uses `↪` instead of `:` as the separator so worktree sessions are visually distinct.
- Strips noisy `worktree-` / `agent-` prefixes from the branch and caps it at 12 characters.

## Override file

Per-worktree, lives at `$(git rev-parse --git-dir)/claude-session-title`. Because it's inside the gitdir, it's never tracked. Each worktree gets its own override.

## Slash commands

- `/auto-session-title:title-set <name>` — write the override. Title becomes `<repo>:<name>` on the next user prompt.
- `/auto-session-title:title-clear` — remove the override. Title reverts to `<repo>:<branch>`.

## Notes

- Claude Code's built-in `/rename` will be overwritten by the hook on the next prompt. Use `/auto-session-title:title-set` instead — it preserves the project prefix.
- The hook is intentionally **Claude Code only**: it uses the `sessionTitle` field on `UserPromptSubmit` hook output, which isn't part of the Copilot CLI hook surface.
