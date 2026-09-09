---
name: ship
description: >-
  Use this skill whenever the user asks to take in-flight work through the
  full merge lifecycle. Triggers on shorthand prompts like
  "branch/commit/pr/watch/master/pull", "pr/watch/master/pull",
  "watch/master/pull", "push+pr then watch and master/pull", "branch/pr/merge/master/pull",
  "send it", "ship it", "merge it", or terse single words "watch", "merge",
  "pull" when the context implies finishing a PR. Drives staging → commit →
  push → PR create → CI watch → merge wait → post-merge release watch →
  checkout master → pull, using `gh`/`tea` directly (platform detected once
  via git-wait) for every GitHub/Gitea call, and cleans up the worktree if one
  was used. Waits for every CI job to reach a terminal state — including any
  release/publish/deploy workflow that only starts after the merge — before
  reporting success. Skips steps that are already complete instead of redoing
  them.
allowed-tools: Bash
---

# ship — full merge lifecycle orchestrator

**Purpose.** Take whatever in-progress work exists and drive it through the canonical lifecycle: stage → commit → push → PR → watch CI → wait for merge → watch the post-merge release run → return to default branch → pull → clean up the worktree if one was used. Skip any step that's already done.

**The bar for "shipped" is that CI is finished, not that CI is green.** Two
distinct waits are mandatory and are the two most commonly skipped steps:
every job on the PR (step 6), and every job in whatever runs *after* the merge
(step 8). Reporting success while any job is still in flight is a failure of
this skill, even if everything eventually passes.

**Detect the platform once, then call `gh` or `tea` directly.** There is no
wrapper. Step 1 below calls `git-wait platform` a single time; every later
step that needs a hosted-CLI call branches on that result with an explicit
`github:` block (`gh`) and `gitea:` block (`tea`). See the sibling `git-wait`
skill for the full gh-vs-tea command map — don't invent flags beyond what's
documented there.

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

Establish: dirty working tree? on default branch or feature branch? upstream set?

Also detect **whether this checkout is a linked git worktree** — this gates the cleanup in step 9:

```bash
git_dir=$(git rev-parse --git-dir)
git_common_dir=$(git rev-parse --git-common-dir)
# Linked worktree iff the two differ. Normalize with realpath first — on macOS
# /tmp is a symlink to /private/tmp, so a raw string compare can falsely differ.
if [ "$(realpath "$git_dir")" != "$(realpath "$git_common_dir")" ]; then
  echo "linked worktree"   # step 9 cleans it up after a confirmed merge
else
  echo "main checkout"     # step 9 keeps its current behavior
fi
```

This read is non-destructive; it only records context for later.

### 1. Detect platform

```bash
platform=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait platform)
```

`platform` is `github` or `gitea`. Every later step that talks to the hosted
CLI branches on this value once — resolved here, not re-detected per step.

Also resolve the default branch now, since both `github:` and `gitea:` need it later:

```bash
github: default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
gitea:  default=$(tea api repos/{owner}/{repo} | jq -r .default_branch)
```

### 2. Stage and commit

If there are uncommitted changes:

- Show the user what will be staged (`git status --short` + `git diff --stat`).
- Stage **specific files** by name; never `git add -A` or `git add .` (avoids accidentally including secrets or generated files).
- Write a structured commit message: imperative-mood title (e.g. `feat: add tea CLI classifier`), optional body paragraph for larger changes, optional bullet list of specific changes. Match the repo's existing commit-log style — check `git log --oneline -20` first.

Skip this step if the working tree is clean.

### 3. Ensure feature branch

If on the default branch (`master`/`main`), create a feature branch with a conventional prefix (`feat-`, `fix-`, `chore-`, `docs-`, `refactor-`, `test-`) before pushing:

```bash
git checkout -b <prefix>-<short-description>
```

Skip if already on a non-default branch.

### 4. Push

```bash
git push -u origin HEAD
```

`-u` is needed only on first push; if upstream is already tracked, plain `git push` is fine. If the push fails because the remote has new commits, do not force-push — investigate first (someone else may have pushed; `git pull --rebase`, resolve, retry).

### 5. Create PR (if not already open)

Check first:

```bash
github: gh pr list --state open --json number,headRefName \
          --jq --arg b "$(git rev-parse --abbrev-ref HEAD)" '.[] | select(.headRefName==$b) | .number'
gitea:  tea pr list --state open --output json --fields index,head \
          | jq -r --arg b "$(git rev-parse --abbrev-ref HEAD)" '.[] | select(.head==$b) | .index'
```

If no PR exists for the current branch:

```bash
github: gh pr create --title "..." --head "$(git rev-parse --abbrev-ref HEAD)" --base "$default" --body-file - <<'EOF'
## Summary
...

## Test plan
...
EOF

gitea:  tea pr create --title "..." --head "$(git rev-parse --abbrev-ref HEAD)" --base "$default" --description "$(cat <<'EOF'
## Summary
...

## Test plan
...
EOF
)"
```

Pull a concise title from the most recent commit message; pull the body from the commit body plus a short test plan. Note `tea pr create` takes `-d`/`--description` only — no `--body`/`--body-file`.

### 6. Watch CI — **every job, to completion**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait run watch --branch "$(git rev-parse --abbrev-ref HEAD)" --interval 30
```

This is platform-agnostic — it works the same on `github` and `gitea`. It polls until CI passes, fails, or the run disappears. Output includes `status` (`pass|fail|closed|timeout|no-workflow`), `url`, `duration`, and on fail `failed_jobs` with logs piped to stderr.

**"CI passed" means every job on the PR reached a terminal state — not just the
required ones, not just the ones that had registered when you first looked.**
This is the step most often called done too early. Before you treat step 6 as
complete:

- **Enumerate the checks and confirm none are still pending.** On GitHub the
  watcher reads the PR's `statusCheckRollup`, which is a snapshot of the checks
  *registered at that moment*. List them explicitly and eyeball the set:

  ```bash
  github: gh pr view "$(git rev-parse --abbrev-ref HEAD)" \
            --json statusCheckRollup \
            --jq '.statusCheckRollup[] | "\(.name // .context): \(.conclusion // .state // "PENDING")"'
  gitea:  tea api "repos/{owner}/{repo}/actions/runs?limit=20" \
            | jq -r --arg b "$(git rev-parse --abbrev-ref HEAD)" \
                '.workflow_runs[] | select((.head_branch // .branch) == $b)
                 | "\(.name): \(.conclusion // .status)"'
  ```

  `git-wait` itself exposes only `platform`, `pr wait`, and `run watch` — there
  is no `run show`/`run list` subcommand to call here, which is why this
  enumeration goes through `gh`/`tea` directly.

- **A green rollup that is missing a workflow you expected is not a pass.**
  If a workflow is slow to queue, the rollup can read "all success" while that
  workflow has not been added to it yet — the watcher returns `pass` and the
  orchestrator marches on. Compare the check names against the repo's
  workflows (`ls .github/workflows/`, or `gh workflow list`) and re-run the
  watcher if something that should be there is absent.

- **Fan-in checks do not excuse the rest.** A repo may gate merge on a single
  aggregate check (this repo uses `ci-pass`). That check going green is the
  *merge* gate, not proof that every job finished — report the individual job
  results, not just the fan-in.

**On failure:** stop the orchestrator and surface the failure to the user. Do not push fixes silently — let them decide.

### 7. Wait for merge

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait pr wait --branch "$(git rev-parse --abbrev-ref HEAD)" --interval 15
```

Also platform-agnostic. **Gitea has no auto-merge at all** — on `gitea`, this
is waiting on a human to click merge (or on you, if the user asked you to
merge it), not on a bot. On `github`, this waits on the repo's auto-merge
bot if one is configured.

Skip this step if the repo has no auto-merge bot **and** the user hasn't asked you to merge manually. **Never merge the PR yourself unless the user explicitly asks** — merging bypasses CI gating and whatever review/auto-merge workflow the repo relies on:

```bash
github: gh pr merge N --squash --delete-branch   # only after explicit user approval
gitea:  tea pr merge N --style squash            # only after explicit user approval
```

### 8. Watch the post-merge run (release, publish, deploy)

**The lifecycle is not finished when the PR merges.** Step 6 only ever sees
checks attached to the *PR head*. Any workflow triggered by the merge itself —
`on: push` to the default branch, `on: release`, a tag build, a publish or
deploy job — runs **after** step 7 returns and appears **nowhere** in the PR's
checks. Skipping this step is how a ship reports success while the release job
is still running, or has already failed.

After step 7 confirms the merge, resolve **your merge commit** and watch the
runs it caused:

```bash
github: merge_sha=$(gh pr view N --json mergeCommit --jq '.mergeCommit.oid')
gitea:  merge_sha=$(tea api repos/{owner}/{repo}/pulls/N | jq -r .merge_commit_sha)

bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-wait run watch --sha "$merge_sha" --interval 30
```

**Watch by SHA, not by branch.** `run watch --branch` follows a single run —
the newest correlated to that branch. On a PR branch that is right, because one
push means one run. On a default branch it is not: two merges landing close
together produce two runs, and the newest going green says nothing about the
other. Watching `--branch "$default"` here reported `status: pass` off the
second merge's run while the first merge's run was still executing.

`--sha` is scoped to the commit *your* merge produced, so it neither misses a
run nor blocks on somebody else's push. It stays pending while any run for that
commit is pending, and fails if any run — or any job inside one — failed. Apply
the same completeness rule as step 6: every job, not the first to report.

Note `gh` calls the field `mergeCommit` (an object; take `.oid`) — there is no
`mergeCommitSha`. `--sha` needs a full 40-character SHA; it will expand a short
one only when git can resolve it locally, and errors rather than silently
watching nothing.

Determine whether such a workflow exists before deciding this step is a no-op:

```bash
grep -lE '^\s*(push|release|workflow_run):' .github/workflows/*.y*ml 2>/dev/null
```

- **A post-merge workflow exists** → watch it to completion and report its
  result alongside the PR result.
- **None exists** (`no-workflow`, or the grep finds nothing) → say so
  explicitly in the final report. "No release workflow on this repo" is a
  finding; silence is indistinguishable from not having looked.
- **It fails** → surface it immediately. A merged PR with a failed release run
  is a worse state than a blocked PR, because the change is already on the
  default branch. Do not attempt a fix or a revert on your own — tell the user.

### 9. Return to default branch (and clean up the worktree if one was used)

`default` was already resolved in step 1.

**Case A — main checkout** (step 0 reported `main checkout`): unchanged behavior.

```bash
git checkout "$default"
git pull
```

**Case B — linked worktree** (step 0 reported `linked worktree`): only proceed **after the branch has actually merged** (step 7 confirmed the merge). Worktree teardown is destructive and hard to reverse — never run this block on an unmerged branch.

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

## Arguments

When invoked as `/git-tools:ship` with arguments, treat `$ARGUMENTS` as additional context for the commit message or PR title:

- `/git-tools:ship squash` — squash-merge intent
- `/git-tools:ship "fix: drop stale lock"` — use as the commit/PR title verbatim

If `$ARGUMENTS` is empty, infer title and body from the diff and recent commit log.

## Idempotency

Each step probes state first and skips when there's nothing to do. Re-running the orchestrator after a partial run should pick up from wherever it left off — e.g. if the PR is already open, jump to step 6; if CI is already passing, jump to step 7; if the PR is already merged, jump to step 8 (post-merge run), then step 9.

The step-9 worktree cleanup is gated twice: it runs only when step 0 detected a linked worktree **and** the branch has merged. In the main checkout it is skipped entirely (current behavior preserved), and re-running after the worktree is already removed is a no-op — the worktree detection short-circuits.

## What NOT to do

- Do **not** guess `gh`/`tea` flags — use the map in the sibling `git-wait` skill, or run `--help` to confirm.
- Do **not** force-push without explicit user approval (and even then, only `--force-with-lease`).
- Do **not** call `gh pr merge` / `tea pr merge` to manually merge unless the user asked — on GitHub, the auto-merge bot normally handles this; on Gitea there is no auto-merge, so a human (or you, if asked) has to do it.
- Do **not** end the session on a feature branch after a merge — return to the default branch and pull.
- Do **not** report "CI passed" off a partial check set — a rollup that is green only because a workflow has not been queued yet is not a pass. Confirm every expected check is present *and* terminal.
- Do **not** stop watching at the merge. A release/publish/deploy workflow triggered by the merge is invisible to the PR's checks; step 8 exists specifically to catch it, and skipping it is how a failed release gets reported as a successful ship.
- Do **not** treat a single fan-in check (e.g. `ci-pass`) as proof that every job finished — it is the merge gate, not the completion signal.
- Do **not** invent your own polling loop (`until gh pr view ... | grep MERGED; do sleep`) — `git-wait pr wait` and `git-wait run watch` already handle this with proper timeouts and failure detection, on both platforms.
- Do **not** `git worktree remove` the worktree you are standing in — `cd` into the main worktree first, then remove.
- Do **not** `--force`-remove a worktree with uncommitted or untracked changes without explicit user approval.
- Do **not** `git branch -D` (force-delete) without confirming first — a `git branch -d` refusal usually signals a squash merge, not work that's safe to discard blindly.
- Do **not** check out a branch that is already live in another worktree (`git` refuses with `already used by worktree at ...`).

## Reporting back

After the lifecycle completes, give the user a one-line summary: PR number + URL, CI status, final state (merged/blocked), and that the workspace is back on the default branch.

State the two waits separately, and never imply a job finished that you did not
actually see finish:

- **PR CI** — the individual job results, not just the fan-in check.
- **Post-merge run** — its result, or an explicit "no post-merge workflow on
  this repo" when step 8 found none. If you stopped watching early (timeout,
  the user interrupted, a job was still queued), say exactly that rather than
  rounding it up to a pass.
