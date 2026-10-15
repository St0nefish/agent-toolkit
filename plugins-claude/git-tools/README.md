# Git Tools

GitHub and Gitea tooling for Claude Code. Platform detection plus blocking
waiters (`git-wait`) for PR merges and CI runs, plus a `ship` orchestrator
that drives the full branch / commit / push / PR / watch / return-to-master
lifecycle in one invocation.

## Installation

```bash
claude plugin install St0nefish/agent-toolkit/git-tools
```

## Components

| Component | Type | Trigger |
|-----------|------|---------|
| `git-tools:git-wait` | Skill (model-triggered) | Any GitHub/Gitea CLI op — background guide pointing the model at `gh`/`tea` directly, plus the platform/wait commands |
| `git-tools:ship` | Skill (model-triggered) | Shorthand workflow prompts like `pr/watch/master/pull`, `branch/commit/pr/watch/master/pull`, `push+pr then watch and master/pull`, or terse `watch` / `merge` |
| `/git-tools:ship` | Slash command (user-invoked) | Explicit invocation of the same orchestrator |

## How it works

**All GitHub/Gitea operations — listing, creating, commenting, merging,
closing, viewing logs, raw API calls — use `gh` or `tea` directly.** There is
no wrapper. GitHub repos use `gh`, Gitea repos use `tea`; their flag sets
diverge in non-obvious ways (see the `git-wait` skill for the verified
command map).

`git-wait` (`scripts/git-wait`) covers only what neither CLI provides on its
own:

- `git-wait platform` — echoes `github` or `gitea` for the current repo's
  origin remote, by matching it against configured `tea` logins.
- `git-wait pr wait --branch NAME` — blocks until a PR merges, closes, or
  conflicts, with a progress-aware idle timeout (idle timeout 5 min, hard
  ceiling 60 min by default; tune with `--idle-timeout`/`--timeout`).
- `git-wait run watch --branch NAME` — blocks until CI finishes, aggregating
  per-job status and dumping failed job logs to stderr (same default
  timeouts, plus a 60s initial delay for CI startup).

Both waiters are platform-agnostic — the same invocation works whether the
repo detected as `github` or `gitea`.

## What `ship` does

`ship` runs the canonical merge lifecycle, skipping any step that's already complete:

1. Detect the platform once via `git-wait platform`
2. Stage uncommitted changes (asks before staging if there are any)
3. Ensure work is on a feature branch (creates one if you're on master/main)
4. Commit with a structured message
5. Push to origin (sets upstream on first push)
6. Create the PR via `gh pr create` / `tea pr create` (skipped if already exists)
7. Watch CI via `git-wait run watch` until it passes, fails, or merges
8. Wait for merge via `git-wait pr wait` — on GitHub this waits on an
   auto-merge bot if one is configured; **Gitea has no auto-merge**, so there
   it merges once the required checks are green
9. Return to the default branch and `git pull`

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| `gh` | Yes* | GitHub CLI |
| `tea` | Yes* | Gitea CLI |
| `jq` | Yes | JSON parsing |
| `git` | Yes | Remote URL detection |

*One of `gh` or `tea` is required depending on your remote host.
