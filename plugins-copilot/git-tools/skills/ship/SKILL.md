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
  the git-cli wrapper for every GitHub/Gitea call. Skips steps that are
  already complete instead of redoing them.
allowed-tools: Bash
---

# ship — full merge lifecycle orchestrator

**Purpose.** Take whatever in-progress work exists and drive it through the canonical lifecycle: stage → commit → push → PR → watch CI → wait for merge → return to default branch → pull. Skip any step that's already done.

**Always use the `git-cli` wrapper** at `${COPILOT_PLUGIN_ROOT}/scripts/git-cli` for every GitHub/Gitea call. Never invoke raw `gh` or `tea` directly — the wrapper auto-detects the platform from the git remote so the same procedure works on both. See the sibling `git-cli` skill for full command reference.

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

Establish: dirty working tree? on default branch or feature branch? upstream set? Determine the default branch via `${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo default-branch`.

### 1. Stage and commit

If there are uncommitted changes:

- Show the user what will be staged (`git status --short` + `git diff --stat`).
- Stage **specific files** by name; never `git add -A` or `git add .` (avoids accidentally including secrets or generated files).
- Write a structured commit message: imperative-mood title (e.g. `feat: add tea CLI classifier`), optional body paragraph for larger changes, optional bullet list of specific changes. Match the repo's existing commit-log style — check `git log --oneline -20` first.

Skip this step if the working tree is clean.

### 2. Ensure feature branch

If on the default branch (`master`/`main`), create a feature branch with a conventional prefix (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`) before pushing:

```bash
git checkout -b <prefix>/<short-description>
```

Skip if already on a non-default branch.

### 3. Push

```bash
git push -u origin HEAD
```

`-u` is needed only on first push; if upstream is already tracked, plain `git push` is fine. If the push fails because the remote has new commits, do not force-push — investigate first (someone else may have pushed; `git pull --rebase`, resolve, retry).

### 4. Create PR (if not already open)

Check first:

```bash
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr list --state open --limit 50 \
  | jq -r --arg b "$(git rev-parse --abbrev-ref HEAD)" '.[] | select(.head==$b) | .number'
```

If no PR exists for the current branch:

```bash
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr create --title "..." --head "$(git rev-parse --abbrev-ref HEAD)" --body <<'EOF'
## Summary
...

## Test plan
...
EOF
```

Pull a concise title from the most recent commit message; pull the body from the commit body plus a short test plan.

### 5. Watch CI

```bash
${COPILOT_PLUGIN_ROOT}/scripts/git-cli run watch --branch "$(git rev-parse --abbrev-ref HEAD)" --timeout 600 --interval 30
```

This polls until CI passes, fails, or merges. Output includes `status` (`pass|fail|closed|timeout|no-workflow`), `url`, `duration`, and on fail `failed_jobs` with logs piped to stderr.

**On failure:** stop the orchestrator and surface the failure to the user. Do not push fixes silently — let them decide.

### 6. Wait for merge

If the repo has an auto-merge bot (this repo's `st0nefish-ci` enables auto-merge on PR open), wait for the merge to complete:

```bash
${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr wait --branch "$(git rev-parse --abbrev-ref HEAD)" --timeout 300 --interval 15
```

Skip this step if the repo does not auto-merge. **Never call `git-cli pr merge` to merge manually unless the user explicitly asks** — that bypasses CI gating and the auto-merge workflow.

### 7. Return to default branch

```bash
default=$(${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo default-branch)
git checkout "$default"
git pull
```

This is the step most often forgotten — always run it after merge unless the user explicitly says otherwise.

## Idempotency

Each step probes state first and skips when there's nothing to do. Re-running the orchestrator after a partial run should pick up from wherever it left off — e.g. if the PR is already open, jump to step 5; if CI is already passing, jump to step 6; if the PR is already merged, jump to step 7.

## What NOT to do

- Do **not** invoke raw `gh` or `tea` — always go through `git-cli`.
- Do **not** force-push without explicit user approval (and even then, only `--force-with-lease`).
- Do **not** call `gh pr merge` / `tea pr merge` to manually merge unless the user asked — the auto-merge bot handles this.
- Do **not** end the session on a feature branch after a merge — return to the default branch and pull.
- Do **not** invent your own polling loop (`until gh pr view ... | grep MERGED; do sleep`) — `git-cli pr wait` and `git-cli run watch` already handle this with proper timeouts and failure detection.

## Reporting back

After the lifecycle completes, give the user a one-line summary: PR number + URL, CI status, final state (merged/blocked), and that the workspace is back on the default branch.
