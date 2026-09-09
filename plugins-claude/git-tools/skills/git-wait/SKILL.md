---
user-invocable: false
name: git-wait
description: >-
  Guide for GitHub/Gitea CLI work. Use `gh` and `tea` DIRECTLY for issues,
  PRs, CI runs, repo, and API calls — there is no wrapper anymore. Reach for
  `git-wait` only to detect which platform a repo uses, and to block until a
  PR merges or a CI run finishes, instead of hand-rolling a poll loop.
allowed-tools: Bash
---

# git-wait

`git-wait` is **not** a CLI wrapper. It replaced `git-cli`, which was deleted.
For every GitHub/Gitea operation — listing, creating, commenting, merging,
closing, viewing logs, raw API calls — invoke `gh` or `tea` **directly**.
`git-wait` exists only for two things neither CLI gives you on its own:

1. **Platform detection** — matching the git remote hostname against
   configured `tea` logins, so a caller knows whether to reach for `gh` or
   `tea`.
2. **Blocking waits** — `pr wait` blocks until a PR reaches a terminal state,
   and `run watch` blocks until CI finishes, both with a progress-aware idle
   timeout. Neither `gh` nor `tea` has an equivalent that covers both
   platforms.

**Never hand-roll a polling loop** (`until gh pr view ... | grep MERGED; do
sleep ...; done`) — use `git-wait pr wait` / `git-wait run watch` instead.
They already handle timeouts, idle detection, and terminal-state parsing
correctly on both platforms.

## The three commands

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform
```

Echoes `github` or `gitea` for the current repo's `origin` remote. Call this
once per session/task and branch on the result — every subsequent hosted-CLI
call needs to know which tool to use.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait pr wait --branch NAME \
  [--timeout 3600] [--idle-timeout 300] [--interval 15]
```

Blocks until the PR for `NAME` merges, closes, or conflicts.
Output: `status: merged|closed|blocked|timeout|error`, plus `pr_number`,
`url`, `duration`, and (when relevant) `reason`.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait run watch (--branch NAME | --sha SHA) \
  [--initial-delay 60] [--timeout 3600] [--idle-timeout 300] [--interval 15]
```

Blocks until CI finishes.
Output: `status: pass|fail|closed|timeout|no-workflow`, plus `url`,
`duration`, and (on failure) `failed_jobs`. Failed job logs are printed to
stderr.

**Pick the right scope — this is a real trap.** `--branch` follows **one** run:
the newest correlated to that branch. That is correct for a PR branch, where a
push means a run. It is wrong on a **default branch**, where two merges landing
close together produce two runs — the newest going green ends the watch while
the other is still executing, and the watcher reports `status: pass`.

`--sha` watches **every** run for one commit: pending while any of them is
pending, failing if any run (or any job inside one) failed. Use it for anything
post-merge — a release, publish, or deploy run — where you care about the runs
one specific merge caused. Pass one flag or the other, never both.

`--sha` needs a full 40-character SHA. A short one is expanded via git when the
commit is resolvable locally and rejected otherwise, because `gh run list
--commit` matches nothing on a short SHA without erroring — which would
otherwise surface as a misleading `no-workflow`.

`timeout` is the hard ceiling; `idle-timeout` is the no-progress window,
reset on every observed change, so a long-running CI suite runs to
completion instead of being cut off by a flat wall clock. Either bound is
disabled by passing `0`.

Exit codes: `0` terminal state reached (check `status:` for pass/fail),
`1` usage error, `2` timeout, `3` platform detection failure or no PR/workflow
found, `4` command failed.

## gh vs. tea command map

Verified against `gh` 2.100.0 and `tea` 0.15.1. Don't guess beyond this
table — if you need a flag that isn't listed, run `gh <cmd> --help` or
`tea <cmd> --help` yourself and confirm before using it.

| task | gh | tea |
|---|---|---|
| open PR | `gh pr create --title T --head B --base M --body-file -` (`-F -` reads stdin) | `tea pr create --title T --head B --base M --description D` — NO `--body`, NO `--body-file`; only `-d`/`--description`, inline text. From a file: `--description "$(cat FILE)"` |
| list PRs | `gh pr list --state open --json number,title,headRefName,url` | `tea pr list --state open --output json --fields index,title,head,url` |
| PR states | `open` / `closed` / `merged` / `all` | `all` / `open` / `closed` ONLY — no `merged`; a merged PR reports state `closed`, and `tea pr list` omits the `merged` boolean entirely. To tell merged from closed: `tea api repos/{owner}/{repo}/pulls/N \| jq -r .merged` |
| merge PR | `gh pr merge N --squash --delete-branch`; `--auto` enables auto-merge | `tea pr merge N --style squash` — no `--auto`; **Gitea has no auto-merge at all** |
| create issue | `gh issue create --title T --body-file - --label L --assignee U` | `tea issues create --title T --description D --labels L --assignees U` (PLURAL flags, comma-separated single string) |
| comment | `gh issue comment N --body-file -` | `tea comment N "text"` |
| close issue | `gh issue close N` | `tea issues close N` |
| CI runs | `gh run list --branch B --json databaseId,status,conclusion,workflowName --limit N`; `gh run view ID --log-failed` | `tea actions runs list` — its server-side `--branch` filter is UNRELIABLE (Gitea leaves `head_branch` empty on `pull_request` runs), and `tea actions runs view` IGNORES `--output json` and prints a human table. Use `tea api repos/{owner}/{repo}/actions/runs` instead. |
| default branch | `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` | `tea api repos/{owner}/{repo} \| jq -r .default_branch` |
| whoami | `gh api user --jq .login` | `tea whoami` |
| raw API | `gh api PATH` | `tea api PATH` — both substitute `{owner}`/`{repo}` |

Notes:

- `tea pulls` is the canonical subcommand name; `tea pr` is an alias for it.
- Suppress color with `GH_NO_COLOR=1` / `NO_COLOR=1` when parsing CLI output
  as text or JSON — ANSI codes otherwise corrupt `jq`/`grep` parsing.
- When a task doesn't fit the map above (e.g. reviews, labels, milestones),
  check `gh <cmd> --help` / `tea <cmd> --help` rather than assuming parity
  between the two CLIs — their flag sets diverge in ways that aren't always
  intuitive (see the PR-create and PR-state rows above).
