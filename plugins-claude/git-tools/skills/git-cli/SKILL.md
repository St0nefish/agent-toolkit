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
- `pr wait --branch NAME` — poll until merged/closed/blocked. Progress-aware: won't time out while CI or auto-merge is still active (idle timeout 5 min, hard ceiling 60 min; tune with `--idle-timeout`/`--timeout`). **Use this instead of writing your own poll loop.**
- `run watch --branch NAME` — poll CI to pass/fail/timeout with proper terminal-state detection. Waits through long runs up to a 60 min ceiling (tune with `--timeout`). **Use this instead of writing your own poll loop.**
- `run show <id>` — aggregates per-job status on Gitea so failed jobs don't get masked by a run-level success (#87).
- `issue comment list <N>` / `delete <id>` / `edit <id> [--body ...]` — read, remove, and update comments. Use `list` to verify a comment posted (the add command returns the new comment's `id`, so you never need to blind-retry and risk a double-post).
- `api <path> [-X METHOD] [-f key=val ...]` — raw authenticated `gh`/`tea api` passthrough; the escape hatch when the wrapper lacks a capability. The `<path>` must come first. Output is the backend's **raw** JSON (not normalized) — supply your own `--jq` or pipe.

## Body input

`--body TEXT` takes an inline argument (matches `gh`/`tea`) and never reads stdin —
use it for short, single-line bodies:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr comment 42 --body "LGTM"
```

For multi-line bodies, read from stdin with `--body-file -` (heredoc or pipe), or
from disk with `--body-file FILE`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue create --title "Bug: ..." --label bug --body-file - <<'EOF'
## Problem
...
EOF

${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr create --title "..." --head my-branch --body-file /tmp/pr-body.md
```

`--body-file -` never hangs: if stdin is an open pipe with no data/EOF it errors
after `GIT_CLI_STDIN_TIMEOUT` seconds (default 10) instead of blocking.

## Normalized JSON output

All commands return JSON with a consistent schema across platforms — **including the write commands** (`issue`/`pr create`, `issue`/`pr comment`, `comment edit`), so every result is parseable and carries a definitive success object. Read commands (`issue`/`pr list`/`show`) return the full issue/PR object:

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

Write commands return a compact object:

- **`issue`/`pr create`** → `{number, url}` (follow with `issue show <N>` for the full object).
- **`issue`/`pr comment`, `comment edit`** → the comment `{id, author, body, html_url, created_at}`. The `id` is the success signal — confirm a post without blind-retrying.
- **`comment delete`** → `{deleted: true, id}`.

The only un-normalized command is `api`, which is a deliberate raw passthrough.

> **Pagination:** `issue comment list` fetches all pages on GitHub (`gh api --paginate`); on Gitea it returns the server's default page size, so a very long thread may be truncated. For verify-after-write this is sufficient.

Downstream skills (e.g. `session/*`) depend on this shape — don't bypass the wrapper just to get raw `gh`/`tea` output.
