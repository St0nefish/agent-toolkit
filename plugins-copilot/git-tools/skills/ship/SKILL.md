---
user-invocable: false
name: ship
description: >-
  Use this skill whenever the user asks to take in-flight work through the
  full merge lifecycle. Triggers on shorthand prompts like
  "branch/commit/pr/watch/master/pull", "pr/watch/master/pull",
  "watch/master/pull", "push+pr then watch and master/pull", "branch/pr/merge/master/pull",
  "send it", "ship it", "merge it", or terse single words "watch", "merge",
  "pull" when the context implies finishing a PR. Drives staging → commit →
  push → PR create → CI watch → merge wait → checkout master → pull, using
  native host tooling (gh on GitHub, host-native equivalent on Gitea) for
  every call, and cleans up the worktree if one was used. Skips steps that are
  already complete instead of redoing them.
allowed-tools: Bash
---

# ship — full merge lifecycle orchestrator

**Purpose.** Take whatever in-progress work exists and drive it through the canonical lifecycle: stage → commit → push → PR → watch CI → wait for merge → return to default branch → pull → clean up the worktree if one was used. Skip any step that's already done.

Use native host tooling for every GitHub/Gitea call. On GitHub repos, prefer `gh`. On Gitea or other hosts, use the equivalent host-native CLI or API tooling. See the sibling `git-cli` skill for the full command reference.

## When to use

Trigger on any shorthand that means "finish this PR":

- `branch/commit/pr/watch/master/pull` (and reorderings)
- `pr/watch/master/pull`
- `watch/master/pull`
- `push+pr, then watch and master/pull`
- `branch/pr/merge/master/pull`
- `send it`, `ship it`, `merge it`, `let's merge that`
- terse single words `watch`, `merge`, `pull` when the surrounding context already involves a PR

If the user explicitly invokes `/git-tools:ship`, use this same procedure.

## Procedure

Run these steps in order. **Detect and skip** any step that is already complete; do not redo work.

### 0. Read state

```bash
git status --porcelain=v1 -b
git rev-parse --abbrev-ref HEAD
```

Establish: dirty working tree? on default branch or feature branch? upstream set? Determine the default branch via `git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||'`.

Also detect **whether this checkout is a linked git worktree** — this gates the cleanup in step 7:

```bash
git_dir=$(git rev-parse --git-dir)
git_common_dir=$(git rev-parse --git-common-dir)
# Linked worktree iff the two differ. Normalize with realpath first — on macOS
# /tmp is a symlink to /private/tmp, so a raw string compare can falsely differ.
if [ "$(realpath "$git_dir")" != "$(realpath "$git_common_dir")" ]; then
  echo "linked worktree"   # step 7 cleans it up after a confirmed merge
else
  echo "main checkout"     # step 7 keeps its current behavior
fi
```

This read is non-destructive; it only records context for later.

### 1. Stage and commit

If there are uncommitted changes:

- Show the user what will be staged (`git status --short` + `git diff --stat`).
- Stage **specific files** by name; never `git add -A` or `git add .` (avoids accidentally including secrets or generated files).
- Write a structured commit message: imperative-mood title (e.g. `feat: add tea CLI classifier`), optional body paragraph for larger changes, optional bullet list of specific changes. Match the repo's existing commit-log style — check `git log --oneline -20` first.

Skip this step if the working tree is clean.

### 2. Ensure feature branch

If on the default branch (`master`/`main`), create a feature branch with a conventional prefix (`feat-`, `fix-`, `chore-`, `docs-`, `refactor-`, `test-`) before pushing:

```bash
git checkout -b <prefix>-<short-description>
```

Skip if already on a non-default branch.

### 3. Push

```bash
git push -u origin HEAD
```

`-u` is needed only on first push; if upstream is already tracked, plain `git push` is fine. If the push fails because the remote has new commits, do not force-push — investigate first (someone else may have pushed; `git pull --rebase`, resolve, retry).

### 4. Create PR (if not already open)

Check first (on GitHub):

```bash
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state open --json number,url
```

On Gitea or other hosts, use the equivalent host-native PR listing command.

If no PR exists for the current branch, create one (on GitHub):

```bash
gh pr create --title "..." --head "$(git rev-parse --abbrev-ref HEAD)" --body-file - <<'EOF'
## Summary
...

## Test plan
...
EOF
```

Pull a concise title from the most recent commit message; pull the body from the commit body plus a short test plan.

### 5. Watch CI

Poll the run associated with the current branch until it passes, fails, or the PR merges. On GitHub:

```bash
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 1 --json databaseId,status,conclusion,url
gh run watch <run-id> --exit-status
```

On Gitea or other hosts, use the host-native CI listing/watching command. Time-box polling (e.g. 600s overall, 30s interval) and surface the failure or timeout clearly. Output should include `status` (`pass|fail|closed|timeout|no-workflow`), `url`, `duration`, and on fail the failing job names with logs.

**On failure:** stop the orchestrator and surface the failure to the user. Do not push fixes silently — let them decide.

### 6. Wait for merge

If the repo has an auto-merge bot (this repo's `st0nefish-ci` enables auto-merge on PR open), poll the PR until merged:

```bash
gh pr view <number> --json state,mergedAt
```

Stop when `mergedAt` is non-null (status: merged) or `state` becomes `CLOSED` without merge. Time-box this poll (e.g. 300s overall, 15s interval). On Gitea, use the host-native PR view command.

Skip this step if the repo does not auto-merge. **Never call `gh pr merge` to merge manually unless the user explicitly asks** — that bypasses CI gating and the auto-merge workflow.

### 7. Return to default branch (and clean up the worktree if one was used)

Always determine the default branch first:

```bash
default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||')
```

**Case A — main checkout** (step 0 reported `main checkout`): unchanged behavior.

```bash
git checkout "$default"
git pull
```

**Case B — linked worktree** (step 0 reported `linked worktree`): only proceed **after the branch has actually merged** (step 6 confirmed the merge). Worktree teardown is destructive and hard to reverse — never run this block on an unmerged branch.

1. Capture identifiers **while still inside the linked worktree** (these are per-worktree):

   ```bash
   linked_wt=$(git rev-parse --show-toplevel)
   feature_branch=$(git rev-parse --abbrev-ref HEAD)   # literal "HEAD" if detached
   main_wt=$(git worktree list --porcelain | awk 'NR==1 && /^worktree /{sub(/^worktree /,""); print}')
   ```

2. **Cleanliness gate.** If the worktree has uncommitted or untracked changes, do **not** remove it automatically:

   ```bash
   git -C "$linked_wt" status --porcelain
   ```

   - Empty output → clean; proceed to remove it automatically.
   - Non-empty → stop and ask the user whether to discard those changes (`git worktree remove --force`) before doing anything destructive.

3. Move into the main worktree and refresh — you cannot reliably remove the worktree you are standing in (its working directory becomes invalid):

   ```bash
   cd "$main_wt"
   git checkout "$default"
   git pull
   ```

4. Remove the merged worktree and prune stale metadata:

   ```bash
   git worktree remove "$linked_wt"   # add --force ONLY after explicit user approval when dirty
   git worktree prune
   ```

5. Delete the now-merged local branch (skip when `feature_branch` is `HEAD`, i.e. detached):

   ```bash
   git branch -d "$feature_branch"
   ```

   `-d` is the safe form — it refuses if git doesn't see the branch as fully merged. A failure usually means a **squash merge** (the branch tip is not an ancestor of the merge commit). Tell the user and ask before force-deleting:

   ```bash
   git branch -D "$feature_branch"   # only after the user confirms
   ```

Returning to the default branch is the step most often forgotten — always run it after merge (in either case) unless the user explicitly says otherwise.

## Idempotency

Each step probes state first and skips when there's nothing to do. Re-running the orchestrator after a partial run should pick up from wherever it left off — e.g. if the PR is already open, jump to step 5; if CI is already passing, jump to step 6; if the PR is already merged, jump to step 7.

The step-7 worktree cleanup is gated twice: it runs only when step 0 detected a linked worktree **and** the branch has merged. In the main checkout it is skipped entirely (current behavior preserved), and re-running after the worktree is already removed is a no-op — the worktree detection short-circuits.

## What NOT to do

- Do **not** invoke `tea` directly on Gitea — use the host-native CLI through its own canonical entry point or the API.
- Do **not** force-push without explicit user approval (and even then, only `--force-with-lease`).
- Do **not** call `gh pr merge` / `tea pr merge` to manually merge unless the user asked — the auto-merge bot handles this.
- Do **not** end the session on a feature branch after a merge — return to the default branch and pull.
- Do **not** invent your own polling loop without time-boxing — bound every wait with a sensible timeout and a clear "no decision yet" exit.
- Do **not** `git worktree remove` the worktree you are standing in — `cd` into the main worktree first, then remove.
- Do **not** `--force`-remove a worktree with uncommitted or untracked changes without explicit user approval.
- Do **not** `git branch -D` (force-delete) without confirming first — a `git branch -d` refusal usually signals a squash merge, not work that's safe to discard blindly.
- Do **not** check out a branch that is already live in another worktree (`git` refuses with `already used by worktree at ...`).

## Reporting back

After the lifecycle completes, give the user a one-line summary: PR number + URL, CI status, final state (merged/blocked), and that the workspace is back on the default branch.
