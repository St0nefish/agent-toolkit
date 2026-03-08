---
user-invocable: false
name: git-cli
description: >-
  Interact with GitHub and Gitea issue trackers and CI systems. List and show
  issues, file bugs, comment on issues or PRs, list and show pull requests,
  and fetch CI run logs — all from any repo context without leaving the session.
allowed-tools: Bash
---

# git-cli

Use `${COPILOT_PLUGIN_ROOT}/scripts/git-cli` to interact with the issue tracker and CI
system for the current repository. Platform (GitHub or Gitea) is auto-detected from the
git remote — no configuration needed.

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
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue list [--limit N] [--state open|closed|all] [--label LABEL] [--assignee USER]

# Show a single issue with full body and comments
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue show <number>

# Create an issue (--body-file accepts a markdown file)
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue create --title "Title" --body-file /tmp/body.md [--label bug]

# Add a comment (use --body-file for multi-line structured content)
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body-file /tmp/comment.md
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue comment <number> --body "Short comment"

# Close or reopen
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue close <number>
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue reopen <number>
```

### Pull Requests

```bash
# List PRs
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr list [--state open|closed|merged|all] [--limit N]

# Show a single PR with details
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr show <number>

# Create a PR (auto-assigns to current user)
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr create --title "Title" --head branch --base main --body-file /tmp/pr.md

# Comment on a PR
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr comment <number> --body-file /tmp/comment.md

# Merge or close
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr merge <number> [--squash | --rebase]
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr close <number>
```

### CI Runs

```bash
# List recent runs (JSON with id, status, workflow, branch, event, started_at)
${COPILOT_PLUGIN_ROOT}/scripts/git-cli run list [--limit N] [--status failure|success|pending] [--branch BRANCH]

# Show details of a specific run
${COPILOT_PLUGIN_ROOT}/scripts/git-cli run show <run-id>

# Fetch logs (--failed-only shows only failing steps on GitHub)
${COPILOT_PLUGIN_ROOT}/scripts/git-cli run logs <run-id>
${COPILOT_PLUGIN_ROOT}/scripts/git-cli run logs <run-id> --failed-only
```

### Repo / User

```bash
${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo default-branch   # e.g. "main" or "master"
${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo info             # name, description, stars, etc.
${COPILOT_PLUGIN_ROOT}/scripts/git-cli user whoami           # {"login": "username"}
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
${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue create --title "Bug: ..." --body-file /tmp/issue.md --label bug
```
