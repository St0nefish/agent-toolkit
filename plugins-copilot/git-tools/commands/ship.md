---
description: "Drive the full branch / commit / push / PR / watch / merge / return-to-master lifecycle in one go"
allowed-tools: Bash, Read, AskUserQuestion
---

Take whatever in-progress work exists in this repo and drive it through the canonical merge lifecycle. Skip any step that is already complete instead of redoing it.

This command invokes the `ship` skill — see the sibling `ship` skill for the full procedure. The summary:

1. **Detect the platform once**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform` → `github` or `gitea`. Every later hosted-CLI call branches on this.
2. **Stage and commit** any uncommitted changes (specific files only — never `git add -A`/`.`).
3. **Ensure a feature branch** with a conventional prefix (`feat-`, `fix-`, `chore-`, `docs-`, …); create one if currently on the default branch.
4. **Push** to origin (`-u` on first push).
5. **Create the PR** — `gh pr create --title T --head B --base M --body-file -` on GitHub; `tea pr create --title T --head B --base M --description D` on Gitea (note: `tea` takes `-d/--description` only, no `--body`/`--body-file`) — if one is not already open for the branch.
6. **Watch CI** via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait run watch --branch NAME` until it passes, fails, or merges. On failure, stop and surface the failure; do not push fixes silently.
7. **Wait for merge** via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait pr wait --branch NAME`. On GitHub this waits on an auto-merge bot if the repo has one. **Gitea has no auto-merge at all** — there this waits on a human to merge, or on you only if the user explicitly asked you to merge (`gh pr merge N --squash --delete-branch` / `tea pr merge N --style squash`). Never merge unless explicitly asked — merging bypasses CI gating and any auto-merge/review workflow.
8. **Return to the default branch** and `git pull`. If the work was done in a linked git worktree, switch back to the main worktree first, then (after the merge) remove the merged worktree — asking before discarding any uncommitted changes — prune, and delete the merged branch.

Never hand-roll a polling loop (`until gh pr view ... | grep MERGED; do sleep`) — `git-wait pr wait` / `git-wait run watch` already handle timeouts and terminal-state detection on both platforms. Never guess `gh`/`tea` flags beyond what's documented in the sibling `git-wait` skill — confirm with `--help` if unsure.

When done, report a one-line summary: PR number + URL, CI status, final state, and confirmation that the workspace is back on the default branch.

If $ARGUMENTS is non-empty, treat it as additional context for the commit message or PR title (e.g. `/git-tools:ship squash` → squash-merge intent; `/git-tools:ship "fix: drop stale lock"` → use as the commit/PR title). Any line in `$ARGUMENTS` matching `^([Cc]loses|[Ff]ixes) #[0-9]+` is a closing line: do not treat it as title/commit text — append it verbatim to the PR body so the linked issue auto-closes on merge. If a PR is already open for the branch, the creation-time append never ran, so check the existing PR body for each closing line and append only the missing ones: GitHub: `gh pr view N --json body --jq .body`, then `gh pr edit N --body-file -` with the full existing body plus the new lines; Gitea: read the body with `tea pulls N --output json --fields description`, then `tea pulls edit N --description "<full body + new lines>"` (replaces the whole body). If the edit fails, post the lines as a PR comment (`tea comment N "..."`) and tell the user the body could not be updated, since a comment does not auto-close the issue.
