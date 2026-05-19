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

Use native host tooling to interact with the issue tracker and CI system for the
current repository. On GitHub repos, prefer `gh`. On Gitea or other hosts, use
the equivalent host-native CLI or API tooling if it is available.

## When to use this skill

- File a bug or enhancement issue discovered mid-session
- Check open issues to understand what work is planned or in progress
- Post a progress comment on a linked issue
- Check CI run status or fetch logs for a failing build
- Inspect the current state of a pull request

## Available commands

### Issues

```bash
# List open issues
gh issue list --limit N --state open --json number,title,state,labels,assignees,url

# Show a single issue with full body and comments
gh issue view <number> --json number,title,body,state,author,labels,assignees,comments,url

# Create an issue (pipe body via heredoc)
gh issue create --title "Title" --label bug --body-file - <<'EOF'
## Problem
...
EOF

# Add a comment
gh issue comment <number> --body-file - <<'EOF'
Progress update...
EOF
gh issue comment <number> --body 'LGTM'

# Close or reopen
gh issue close <number>
gh issue reopen <number>
```

### Pull Requests

```bash
# List PRs
gh pr list --state open --limit N --json number,title,state,headRefName,baseRefName,url

# Show a single PR with details
gh pr view <number> --json number,title,body,state,headRefName,baseRefName,author,reviewRequests,comments,url

# Create a PR
gh pr create --title "Title" --head branch --base main --body-file - <<'EOF'
## Summary
...

## Test plan
...
EOF

# Comment on a PR
gh pr comment <number> --body-file - <<'EOF'
Review follow-up...
EOF

# Merge or close
gh pr merge <number> [--squash | --rebase]
gh pr close <number>
```

### CI Runs

```bash
# List recent runs
gh run list --limit N --json databaseId,status,workflowName,headBranch,event,startedAt,url

# Show details of a specific run
gh run view <run-id> --json databaseId,status,conclusion,workflowName,headBranch,url,jobs

# Fetch logs
gh run view <run-id> --log
gh run view <run-id> --log-failed
```

### Repo / User

```bash
gh repo view --json defaultBranchRef,name,description,url
gh api user --jq '{login: .login}'
```

## Output format

Prefer JSON-shaped output when scripting:

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

Use `--json ...` plus `jq` to normalize the fields you need for the current task.
If the remote is not GitHub, use the equivalent host-native tooling and shape the
output into a similarly small JSON object before reasoning over it.

## Writing issue/PR bodies

Pipe the body via a heredoc. No temp file, no cleanup:

```bash
gh issue create --title "Bug: ..." --label bug --body-file - <<'EOF'
## Problem
...

## Steps to reproduce
...
EOF
```

If the host is not GitHub, use the equivalent host-native command or API call
and preserve the same heredoc/stdin pattern where possible.
