# Git Tools

GitHub and Gitea tooling for Claude Code. Combines a unified CLI wrapper (`git-cli`) for issues, pull requests, and CI runs with a `ship` orchestrator that drives the full branch / commit / push / PR / watch / return-to-master lifecycle in one invocation.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/git-tools
```

## Components

| Component | Type | Trigger |
|-----------|------|---------|
| `git-tools:git-cli` | Skill (model-triggered) | Any GitHub/Gitea CLI op — fires when the model needs to interact with issues, PRs, CI |
| `git-tools:ship` | Skill (model-triggered) | Shorthand workflow prompts like `pr/watch/master/pull`, `branch/commit/pr/watch/master/pull`, `push+pr then watch and master/pull`, or terse `watch` / `merge` |
| `/git-tools:ship` | Slash command (user-invoked) | Explicit invocation of the same orchestrator |

## How the wrapper works

`git-cli` detects the platform from the git remote URL. GitHub repos use `gh`, Gitea repos use `tea`. All output is normalized to consistent JSON regardless of platform.

| Scope | Operations |
|-------|------------|
| Issues | `list`, `show`, `create`, `comment`, `close`, `reopen` |
| Pull Requests | `list`, `show`, `create`, `comment`, `merge`, `close`, `wait` |
| CI Runs | `list`, `show`, `logs`, `watch` |
| Repository | `default-branch`, `info` |
| User | `whoami` |

`pr wait` polls until a PR is merged/closed/blocked, staying alive while CI or auto-merge is still progressing (idle timeout 5 min, hard ceiling 60 min). `run watch` waits for CI completion with a 60s initial delay for CI startup (hard ceiling 60 min).

## What `ship` does

`ship` runs the canonical merge lifecycle, skipping any step that's already complete:

1. Stage uncommitted changes (asks before staging if there are any)
2. Ensure work is on a feature branch (creates one if you're on master/main)
3. Commit with a structured message
4. Push to origin (sets upstream on first push)
5. Create the PR via `git-cli pr create` (skipped if already exists)
6. Watch CI via `git-cli run watch` until it passes, fails, or merges
7. Wait for merge via `git-cli pr wait` if an auto-merge bot is involved
8. Return to the default branch and `git pull`

Each step uses the `git-cli` wrapper rather than raw `gh`/`tea`, keeping behavior consistent across GitHub and Gitea repos.

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `gh` | Yes* | GitHub API |
| `tea` | Yes* | Gitea API |
| `jq` | Yes | JSON normalization |
| `git` | Yes | Remote URL detection |

*One of `gh` or `tea` is required depending on your remote host.
