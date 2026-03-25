---
user-invocable: false
name: git-cli
description: >-
  This skill MUST be used for ALL GitHub and Gitea CLI operations. Never run
  `gh`, `tea`, `gh issue`, `gh pr`, `gh run`, `gh api`, `gh repo`, `tea issues`,
  or `tea pr` directly — always use git-cli instead. This skill should be used
  when the user asks to "list issues", "show issue", "file a bug", "create issue",
  "comment on issue", "list PRs", "show PR", "create PR", "merge PR", "check CI",
  "view run logs", "check build status", or any interaction with GitHub or Gitea
  issue trackers, pull requests, or CI systems. Provides a unified wrapper that
  auto-detects the platform from the git remote.
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

# Create an issue (--body-file accepts a markdown file)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Title" --body-file /tmp/body.md [--label bug]

# Add a comment (use --body-file for multi-line structured content)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body-file /tmp/comment.md
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body "Short comment"

# Close or reopen
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue close <number>
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue reopen <number>
```

### Pull Requests

```bash
# List PRs
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr list [--state open|closed|merged|all] [--limit N]

# Show a single PR with details
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr show <number>

# Create a PR (auto-assigns to current user; --base defaults to repo's primary branch)
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr create --title "Title" --head branch [--base main] [--body-file /tmp/pr.md]

# Comment on a PR
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr comment <number> --body-file /tmp/comment.md

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
# Outputs: status (pass|fail|timeout|no-workflow|unknown), run_id, url, duration, failed_jobs
# "unknown" means polling was unable to determine run state — use `run show <run_id>` to check manually
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

Use `--body-file` with a temporary markdown file for any structured content:

```bash
cat > /tmp/issue.md << 'EOF'
## Problem
...

## Steps to reproduce
...
EOF
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Bug: ..." --body-file /tmp/issue.md --label bug
```
