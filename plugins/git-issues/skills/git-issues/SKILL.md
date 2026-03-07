---
name: git-issues
description: >-
  Interactive issue-to-PR workflow. Loads open issues for the current
  repo (GitHub or Gitea), picks the top 3 by priority, lets you choose one,
  builds an implementation plan, creates a branch, applies the changes, then
  commits, pushes, and opens a PR — all guided step-by-step.
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# git-issues

End-to-end issue workflow: triage → plan → branch → implement → PR.
Works with GitHub and Gitea — platform detection is handled by the wrapper script.

**This skill has three mandatory checkpoints where you MUST stop and wait for user input before continuing. Do not skip or auto-answer them.**

All platform interactions go through the wrapper script:

```
${CLAUDE_PLUGIN_ROOT}/scripts/git-issues <cmd> [args]
```

If the script exits non-zero, surface the error message to the user and stop.

---

## 1 — Fetch and triage

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-issues list --limit 50
```

The **first line** of output is a comment identifying the detected platform and CLI tool, e.g.:
```
# platform=github cli=gh
```
Note this — if you need to run any platform-specific command not covered by this script, use the identified CLI tool (`gh` or `tea`).

The remaining output is JSON with the open issues. Each issue includes its body. If there are no open issues, tell the user and stop.

Rank all issues and select the **top 3** using these signals (highest weight first):

- **Labels**: `critical`, `security`, `blocker`, `bug`, `high-priority`
- **Milestone**: attached to an active milestone
- **Comments**: higher count = higher priority
- **Age**: older issues rank above newer ones

**⛔ CHECKPOINT 1 — STOP HERE.** Use `AskUserQuestion` to present the three candidates and wait for the user to choose. Do not proceed to step 2 until the user responds. Format each choice as:
`#<n> — <title> · <one-sentence rationale>`

---

## 2 — Plan

If the issue body from the list was truncated or you need comments, fetch the full detail:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-issues show <number>
```

Read the relevant source files. Write a plan covering: problem, solution approach, files to change/create, edge cases, and test considerations.

Unless the fix is trivially small (single-line typo, config value, etc.), the plan should include tests. Look for the existing test structure (unit tests, integration tests, test helpers) and propose tests that cover the changed behaviour. If no test infrastructure exists, note that and suggest what would be worth adding.

**⛔ CHECKPOINT 2 — STOP HERE.** Present the full plan to the user, then use `AskUserQuestion` to get explicit approval before touching any files or creating any branches. Do not create a branch or make any changes until the user approves. Choices:

- **Looks good — proceed**
- **Revise** — take feedback, rewrite the plan, re-ask (loop until approved or cancelled)
- **Cancel** — stop, make no changes

---

## 3 — Branch and implement

Only reach this step after the user has explicitly approved the plan in checkpoint 2.

Derive a kebab-case slug (max 5 words) from the issue title and create the branch:

```bash
git checkout -b issue-<number>-<slug>
```

Implement the plan including any tests. Follow existing codebase conventions. Note each file as it's done (`✓ src/foo.ts`). Stop mid-implementation only if an unexpected decision is needed.

---

## 4 — Review

```bash
git --no-pager diff --stat HEAD
```

Summarise what changed and why.

**⛔ CHECKPOINT 3 — STOP HERE.** Use `AskUserQuestion` to get explicit approval before running any git commit, push, or PR commands. Do not commit or push until the user approves. Choices:

- **Approve — commit, push, open PR**
- **Request changes** — apply them and return to this step
- **Abandon** — `git checkout -` and stop

---

## 5 — Commit, push, PR

Only reach this step after the user has explicitly approved in checkpoint 3.

```bash
git add -A
git commit -m "$(printf '<fix|feat|refactor|chore>(<scope>): <title>\n\nResolves #<n>\n\n<imperative-mood description>')"
git push -u origin HEAD
```

Detect the default branch:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' \
  || git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}'
```

Open the PR:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-issues pr \
  --title "<issue title>" \
  --description "$(printf 'Resolves #<n>\n\n## Summary\n\n<2-3 sentences>')" \
  --head issue-<number>-<slug> \
  --base <default-branch>
```

The `Resolves #<n>` closing keyword in the PR description automatically closes the issue when the PR is merged. Always include it — never omit or reword it.

If the PR command fails, share the push URL and ask the user to open it in the web UI. Report the PR URL to the user.
