# Session

Work session management with issue-linked branches, cross-machine handoff, and structured checkpoints.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/session
```

## How It Works

The session plugin organizes development around an **issue-based workflow**. Each work session links a git branch to an issue tracker entry (GitHub or Gitea), and all context — checkpoints, handoffs, progress — flows through both the branch and the issue.

The branch naming convention `type/NNN-slug` (e.g. `feature/42-add-export`) is central to the plugin. The issue number is extracted from the branch name and used to:

- Fetch full issue context during catchup/resume
- Post checkpoint and handoff comments to the issue
- Auto-close the issue when the PR merges (via `Resolves #N`)

### Working Without Issues

If your team doesn't use issues, you can still use the plugin. `/session:start` accepts freeform descriptions and creates `wip/<slug>` branches. Checkpoint and handoff context will live in git commit bodies instead of issue comments. The `/session:end` PR workflow works the same either way.

## Commands

| Command | Description |
|---------|-------------|
| `/session:start` | List open issues and active branches, pick one, explore the codebase, and enter plan mode |
| `/session:issue` | Like start but focused on issue selection — ranks by urgency, asks you to pick from top 3 |
| `/session:status` | Lightweight status card — branch, commits ahead, linked issue, uncommitted changes |
| `/session:catchup` | Full context rebuild — reads changed files, fetches issue history, reconstructs state |
| `/session:checkpoint` | Commit all changes, push, and post a structured checkpoint comment to the linked issue |
| `/session:handoff` | Create a WIP commit with handoff metadata, push, and post handoff context to the issue |
| `/session:resume` | List active branches, check one out, and rebuild full context (including handoff data) |
| `/session:end` | Review changes, open a PR, watch CI, wait for merge, return to default branch |
| `/session:reset` | Return to the default branch (warns if uncommitted changes would be lost) |

## Skills (Model-Triggered)

These fire automatically without user invocation:

| Skill | Triggers on |
|-------|-------------|
| `status` | "what was I working on?", "session status", coming back after a break |
| `catchup` | Switching tasks, needing full context rebuild |
| `checkpoint` | Completing a major milestone, context window approaching full |
| `summarize` | Requests to summarize the current repo situation |

## Typical Workflow

```text
/session:start          # pick an issue, explore code, plan
  ... implement ...
  (checkpoint)          # auto-fires after major milestones
/session:handoff        # switching machines? push WIP + context
  --- other machine ---
/session:resume         # pull branch, rebuild context
  ... continue ...
/session:end            # review, PR, watch CI, wait for merge
```

## Cross-Machine Handoff

Handoff stores context in two places so it survives without cloning:

1. **Git commit body** — a `WIP:` commit containing `=== IN PROGRESS ===`, `=== NEXT STEPS ===`, and `=== KEY CONTEXT ===` sections. Travels with `git push`.
2. **Issue comment** — the same structured context posted to the linked issue via `git-cli`. Readable from any browser.

On the receiving machine: `git pull` brings the WIP commit; `/session:resume` reads both sources and reconstructs the full context card.

## Branch Type Detection

When starting from an issue, the branch type is inferred from issue labels:

| Labels | Branch prefix |
|--------|--------------|
| `bug`, `fix` | `bug/` |
| `enhancement`, `feature`, `improvement` | `enhancement/` |
| `docs`, `chore`, `refactor`, `maintenance` | `chore/` |
| (none of the above) | `feature/` |

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `git` | Yes | All branch, commit, and diff operations |
| `gh` | Yes* | GitHub API — issues, PRs, CI |
| `tea` | Yes* | Gitea API — issues, PRs, CI |
| `jq` | Yes | JSON processing in git-cli |

*Either `gh` or `tea` is required depending on your git remote host.

The `git-cli` skill plugin is bundled as a symlinked script — you don't need to install it separately, but you do need the underlying CLI tools.
