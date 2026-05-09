---
user-invocable: false
name: git-cli
description: >-
  MUST be used for ALL GitHub/Gitea CLI operations. Never invoke `gh`, `tea`,
  or their subcommands directly — always go through git-cli. Use for issues,
  PRs, CI runs, repo, and api calls; auto-detects the platform from the git
  remote.
allowed-tools: Bash
---

# git-cli

**CRITICAL: Never run `gh` or `tea` directly.** Always use the wrapper script below.
The current repository may use GitHub or Gitea — the wrapper auto-detects the platform
from the git remote so the correct CLI is used every time. Running `gh` directly will
fail on Gitea repositories and vice versa.

## When to use this skill

- File a bug or enhancement issue discovered mid-session
- Check open issues to understand what work is planned or in progress
- Post a progress comment on a linked issue
- Check CI run status or fetch logs for a failing build
- Inspect the current state of a pull request

## Available commands

### Issues

```bash
# List open issues (returns normalized JSON array)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue list [--limit N] [--state open|closed|all] [--label LABEL] [--assignee USER]

# Show a single issue with full body and comments
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue show <number>

# Create an issue (pipe body to --body via heredoc)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Title" --body [--label bug] <<'EOF'
## Problem
...
EOF

# Add a comment (heredoc for multi-line, printf for short)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body <<'EOF'
Progress update...
EOF
printf 'LGTM' | ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body

# Close or reopen
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue close <number>
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue reopen <number>
```

### Pull Requests

```bash
# List PRs
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr list [--state open|closed|merged|all] [--limit N]

# Show a single PR with details — by number, or by branch name
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr show <number>
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr show --branch <branch>      # resolves to most-recent PR for that branch
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr show --branch "$(git rev-parse --abbrev-ref HEAD)"

# Create a PR (auto-assigns to current user; --base defaults to repo's primary branch)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr create --title "Title" --head branch [--base main] --body <<'EOF'
## Summary
...

## Test plan
...
EOF

# Comment on a PR
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr comment <number> --body <<'EOF'
Review follow-up...
EOF

# Merge or close
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr merge <number> [--squash | --rebase]
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr close <number>

# Wait for a PR to merge (polls until merged, closed, or timeout)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr wait --branch NAME [--timeout 300] [--interval 15]
```

### CI Runs

```bash
# List recent runs (JSON with id, status, workflow, branch, event, started_at)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli run list [--limit N] [--status failure|success|pending] [--branch BRANCH]

# Show details of a specific run
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli run show <run-id>

# Fetch logs (--failed-only shows only failing steps on GitHub)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli run logs <run-id>
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli run logs <run-id> --failed-only

# Watch for CI completion (polls until pass/fail/timeout)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli run watch --branch NAME [--initial-delay S] [--timeout S] [--interval S]
# Outputs: status (pass|fail|closed|timeout|no-workflow), url, duration
# On fail: also emits failed_jobs: <comma-separated names> and dumps failed job logs to stderr
# Cancelled/skipped runs report status: fail with a reason: line so callers
# gating on status: pass stop instead of advancing.
# Per-job status is aggregated on both gh and tea — a run-level "success" with
# any failed job still yields status: fail (Gitea masks job failures behind a
# run-level success, see issue #87).
# On GitHub with a PR: uses statusCheckRollup for reliable CI + merge state detection
# Without a PR: falls back to run list polling
```

### Repo / User

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo default-branch   # e.g. "main" or "master"
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo info             # name, description, stars, etc.
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli user whoami           # {"login": "username"}
```

## Output format

All commands return JSON. Issue and PR objects use a normalized schema:

```json
{
  "number": 42,
  "title": "...",
  "body": "...",
  "state": "open",
  "author": "username",
  "labels": ["bug", "high-priority"],
  "milestone": null,
  "assignees": ["username"],
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z",
  "url": "https://..."
}
```

## Writing issue/PR bodies

Pipe the body to `--body` via a heredoc. No temp file, no cleanup:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Bug: ..." --label bug --body <<'EOF'
## Problem
...

## Steps to reproduce
...
EOF
```

`--body-file FILE` remains available when the body is already on disk, and
`--body-file -` is equivalent to `--body` (reads stdin). There is no
`--body TEXT` form — stdin handles every size from one-liners to full PR
descriptions.
