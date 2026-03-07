---
name: gitea-issues
description: >-
  Interactive Gitea issue-to-PR workflow. Loads open issues for the current
  repo, picks the top 3 by priority, lets you choose one, builds an
  implementation plan, creates a branch, applies the changes, then commits,
  pushes, and opens a PR — all guided step-by-step.
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# gitea-issues

End-to-end Gitea issue workflow: triage → plan → branch → implement → PR.

All `tea` interactions go through the wrapper script:

```
${CLAUDE_PLUGIN_ROOT}/scripts/gitea-issues <cmd> [args]
```

The script exits non-zero with a clear message if `tea` is missing or unauthenticated — surface that to the user and stop.

---

## 1 — Fetch and triage

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gitea-issues list --limit 50
```

Parse the output (JSON if available, tabular text otherwise). If there are no open issues, tell the user and stop.

Rank all issues and select the **top 3** using these signals (highest weight first):

- **Labels**: `critical`, `security`, `blocker`, `bug`, `high-priority`
- **Milestone**: attached to an active milestone
- **Comments**: higher count = higher priority
- **Age**: older issues rank above newer ones

Present them with `AskUserQuestion`. Format each choice as:
`#<n> — <title> · <one-sentence rationale>`

---

## 2 — Plan

Fetch the selected issue's full description:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gitea-issues show <number>
```

Read the relevant source files. Write a plan covering: problem, solution approach, files to change/create, edge cases, and test considerations. Present it to the user, then ask with `AskUserQuestion`:

- **Looks good — proceed**
- **Revise** — take feedback, rewrite, re-ask (loop until approved or cancelled)
- **Cancel**

---

## 3 — Branch and implement

Derive a kebab-case slug (max 5 words) from the issue title and create the branch:

```bash
git checkout -b issue-<number>-<slug>
```

Implement the plan. Follow existing codebase conventions. Note each file as it's done (`✓ src/foo.ts`). Stop only if a decision is needed mid-implementation.

---

## 4 — Review and approve

```bash
git --no-pager diff --stat HEAD
```

Summarise what changed and why, then ask with `AskUserQuestion`:

- **Approve — commit, push, open PR**
- **Request changes** — apply them and return to this step
- **Abandon** — `git checkout -` and stop

---

## 5 — Commit, push, PR

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
${CLAUDE_PLUGIN_ROOT}/scripts/gitea-issues pr \
  --title "<issue title>" \
  --description "$(printf 'Resolves #<n>\n\n## Summary\n\n<2-3 sentences>')" \
  --head issue-<number>-<slug> \
  --base <default-branch>
```

If the PR command fails, share the push URL and ask the user to open it in the Gitea web UI. Report the PR URL to the user.
