# Git CLI

Unified GitHub and Gitea CLI wrapper with auto-detected platform and normalized JSON output. Model-triggered — fires automatically when Claude needs to interact with issues, PRs, or CI.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/git-cli
```

## How It Works

Detects the platform from the git remote URL. GitHub repos use `gh`, Gitea repos use `tea`. All output is normalized to consistent JSON regardless of platform.

## Available Operations

| Scope | Commands |
|-------|----------|
| Issues | `list`, `show`, `create`, `comment`, `close`, `reopen` |
| Pull Requests | `list`, `show`, `create`, `comment`, `merge`, `close`, `wait` |
| CI Runs | `list`, `show`, `logs`, `watch` |
| Repository | `default-branch`, `info` |
| User | `whoami` |

`pr wait` polls until a PR is merged/closed/blocked (default timeout: 300s). `run watch` waits for CI completion with a 60s initial delay for CI startup (default timeout: 600s).

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `gh` | Yes* | GitHub API |
| `tea` | Yes* | Gitea API |
| `jq` | Yes | JSON normalization |
| `git` | Yes | Remote URL detection |

*One of `gh` or `tea` is required depending on your remote host.
