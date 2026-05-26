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

The project prefix is **always** preserved — the override file contains only the suffix.

## Override file

Per-worktree, lives at `$(git rev-parse --git-dir)/claude-session-title`. Because it's inside the gitdir, it's never tracked. Each worktree gets its own override.

## Slash commands

- `/auto-session-title:set <name>` — write the override. Title becomes `<repo>:<name>` on the next user prompt.
- `/auto-session-title:clear` — remove the override. Title reverts to `<repo>:<branch>`.

## Notes

- Claude Code's built-in `/rename` will be overwritten by the hook on the next prompt. Use `/auto-session-title:set` instead — it preserves the project prefix.
- The hook is intentionally **Claude Code only**: it uses the `sessionTitle` field on `UserPromptSubmit` hook output, which isn't part of the Copilot CLI hook surface.
