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

**Always invoke `${CLAUDE_PLUGIN_ROOT}/scripts/git-cli`. Never run `gh` or `tea` directly** — the current repo may use either and the wrapper auto-detects from the git remote. Raw `gh` against a Gitea repo (and vice versa) will hit the wrong API.

## Command reference

Run `${CLAUDE_PLUGIN_ROOT}/scripts/git-cli --help` for the full subcommand list (`issue`, `pr`, `run`, `repo`, `user`) and per-command flags. A few non-obvious ones worth knowing:

- `pr show --branch NAME` — resolve the most-recent PR for a branch.
- `pr wait --branch NAME` — poll until merged/closed/blocked (default 300s). **Use this instead of writing your own poll loop.**
- `run watch --branch NAME` — poll CI to pass/fail/timeout with proper terminal-state detection. **Use this instead of writing your own poll loop.**
- `run show <id>` — aggregates per-job status on Gitea so failed jobs don't get masked by a run-level success (#87).

## Body input

`--body` reads from stdin (heredoc or pipe). No temp files, no `--body TEXT` form:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Bug: ..." --label bug --body <<'EOF'
## Problem
...
EOF

printf 'LGTM' | ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr comment 42 --body
```

`--body-file FILE` is also available (`--body-file -` is equivalent to `--body`).

## Normalized JSON output

All commands return JSON with a consistent schema across platforms. Issue/PR objects use:

```json
{
  "number": 42,
  "title": "...",
  "body": "...",
  "state": "open",
  "author": "username",
  "labels": ["bug"],
  "assignees": ["username"],
  "milestone": null,
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": "2026-01-01T00:00:00Z",
  "url": "https://..."
}
```

Downstream skills (e.g. `session/*`) depend on this shape — don't bypass the wrapper just to get raw `gh`/`tea` output.
