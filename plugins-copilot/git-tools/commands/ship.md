---
description: "Drive the full branch / commit / push / PR / watch / merge / return-to-master lifecycle in one go"
allowed-tools: Bash, Read, AskUserQuestion
---

Take whatever in-progress work exists in this repo and drive it through the canonical merge lifecycle. Skip any step that is already complete instead of redoing it.

This command invokes the `ship` skill — see the sibling `ship` skill for the full procedure. The summary:

1. **Stage and commit** any uncommitted changes (specific files only — never `git add -A`/`.`).
2. **Ensure a feature branch** with a conventional prefix (`feat/`, `fix/`, `chore/`, `docs/`, …); create one if currently on the default branch.
3. **Push** to origin (`-u` on first push).
4. **Create the PR** via `gh pr create` (or the host-native equivalent on Gitea) if one is not already open for the branch.
5. **Watch CI** until it passes, fails, or merges. On failure, stop and surface the failure; do not push fixes silently.
6. **Wait for merge** if the repo has an auto-merge bot. Never invoke `gh pr merge` to merge manually unless the user explicitly asks.
7. **Return to the default branch** and `git pull`.

On GitHub repos, prefer `gh` for every PR, run, and repo call. On Gitea or other hosts, use the equivalent host-native tooling or API.

When done, report a one-line summary: PR number + URL, CI status, final state, and confirmation that the workspace is back on the default branch.

If $ARGUMENTS is non-empty, treat it as additional context for the commit message or PR title (e.g. `/git-tools:ship squash` → squash-merge intent; `/git-tools:ship "fix: drop stale lock"` → use as the commit/PR title).
