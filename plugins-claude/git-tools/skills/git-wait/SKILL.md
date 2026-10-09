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
  [--timeout 14400] [--idle-timeout 300] [--interval 15] [--alert-interval 300]
```

Blocks until the PR for `NAME` merges, closes, or conflicts.
Output: `status: merged|closed|blocked|timeout|error`, plus `pr_number`,
`url`, `duration`, and (when relevant) `reason`.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait run watch (--branch NAME | --sha SHA) \
  [--initial-delay 60] [--timeout 14400] [--idle-timeout 0] [--interval 15] \
  [--alert-interval 300] [--no-run-timeout 600|900] [--settle 0] [--max-poll-failures 10]
```

Blocks until CI finishes.
Output: `status: pass|fail|closed|timeout|no-workflow|error`, plus `url`,
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

**Patience defaults.** A running CI is never aborted for lack of visible
progress: `run watch --idle-timeout` defaults to `0` (disabled; pass N to opt in to
a no-progress window). `pr wait --idle-timeout` defaults to `300` but only
advances while no check is pending (running CI or armed auto-merge resets it), so
a PR waiting on review gives up while a long CI never does; `0` disables.
`--timeout` is a generous hard ceiling (`14400`s = 4h; `0` disables it). Long jobs (start a VM, run an integration suite, tear down)
can stay quiet for a long time. If `status: timeout` does come back, CI was
still running: **re-run the watch**, do not treat it as a result.

**Heartbeat alerts.** While waiting, a line like `git-wait: still running
after 5m (2 run(s) pending: CI, Release)` goes to **stderr** every
`--alert-interval` seconds (default `300`; `0` disables). stdout `key: value`
output is unchanged. Relay these to the user so a long wait is visibly alive.

**`no-workflow` is patient.** `--no-run-timeout` is how long to wait for the
*first* run to appear (counted from the end of `--initial-delay`): `600`s for
`--sha`, `900`s for `--branch` (PR checks can register late). Post-merge workflows trigger by push/tag/
`workflow_run` and can queue minutes late or start only after another workflow
finishes, so `no-workflow` is reported only after that window, with a stderr
line (`no runs yet for <sha>, still waiting (Ns of 600s)`) on every poll. A
*failed* run-list call (network/auth) is not "no runs": it is noted on stderr,
excluded from that window and retried, but `--max-poll-failures N`
consecutive failures (default `10`; `0` disables) end the watch with
`status: error` and exit `4`. A successful poll resets the count.

**`--settle SECS`** (`--sha` only, a usage error with `--branch`; default `0` = off): once every run
is terminal and passing, keep polling `SECS` more before reporting `pass`, so a
chained `workflow_run` workflow that starts late is still watched. Opt in with
`--settle 30` only when such a chain exists.

The `--timeout` ceiling is enforced on every poll, including while waiting for
the first run, settling, or waiting for checks to register. On the `--branch`
PR path, a failed `gh pr view` counts toward `--max-poll-failures`, and a PR
with no checks registered ends as `no-workflow` after `--no-run-timeout`.

Exit codes: `0` terminal state reached (check `status:` for pass/fail),
`1` usage error, `2` timeout, `3` platform detection failure or no PR/workflow
found, `4` command failed.

## Targeting another repo

Put `-C DIR` before the command to run against a repo other than the current
directory — use it instead of `cd`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait -C /path/to/other-repo run watch --branch NAME
```

Only `git-wait` honors `-C`; direct `gh`/`tea` calls against another repo still
need their own `-R OWNER/REPO` / `--repo` flag.

## gh vs. tea command map

Verified against `gh` 2.100.0 and `tea` 0.15.1. Don't guess beyond this
table — if you need a flag that isn't listed, run `gh <cmd> --help` or
`tea <cmd> --help` yourself and confirm before using it.

| task | gh | tea |
|---|---|---|
| open PR | `gh pr create --title T --head B --base M --body-file -` (`-F -` reads stdin) | `tea pr create --title T --head B --base M --description D` — NO `--body`, NO `--body-file`; only `-d`/`--description`, inline text. From a file: `--description "$(cat FILE)"` |
| list PRs | `gh pr list --state open --json number,title,headRefName,url` | `tea pr list --state open --output json --fields index,title,head,url` |
| PR states | `open` / `closed` / `merged` / `all` | `all` / `open` / `closed` ONLY — no `merged`; a merged PR reports state `closed`, and `tea pr list` omits the `merged` boolean entirely. To tell merged from closed: `tea api repos/{owner}/{repo}/pulls/N \| jq -r .merged` |
| merge PR | `gh pr merge N --merge --delete-branch`; `--auto` enables auto-merge | `tea pr merge N --style merge` — no `--auto`; **Gitea has no auto-merge at all** |
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
