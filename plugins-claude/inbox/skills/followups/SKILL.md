---
name: followups
description: "Read-only checklist of the followups logged this session plus a live sweep of loose ends (uncommitted or unpushed work, open PR or worktree, pending questions and decisions)."
disable-model-invocation: true
allowed-tools: Bash
---

# Followups and loose ends

Read-only. List what should be considered before wrapping up; **act on
nothing**. Offer to work through items only after listing them.

## Logged followups

Current tracker output (injected by the harness, not a tool call):

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox --session ${CLAUDE_SESSION_ID} list --kind followup --format md --full`

## Live state (injected)

Working tree and branch:

!`git status --short -b 2>&1 | head -40`

Commits not on the upstream (empty when none or no upstream):

!`git log --oneline '@{u}..' 2>/dev/null | head -20`

Worktrees:

!`git worktree list 2>&1 | head -10`

Open PR for the current branch (empty when none or no CLI):

!`gh pr list --head "$(git branch --show-current)" --state open --json number,title,url 2>/dev/null | head -c 600`

Open questions and decisions in the inbox:

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox --session ${CLAUDE_SESSION_ID} list`

## Reply format

Reply as markdown with these sections, omitting any that are empty:

1. **Followups**: the logged list above, verbatim, as a checklist.
2. **Loose ends**: from the live state, one line each for uncommitted or
   unpushed work, an open PR or leftover worktree, and any pending `Q`/`D` items.
3. **Check from the conversation** (no tool call needed, use what you know):
   background tasks still running, issues that are only partly resolved or not
   yet filed, docs or version bumps this repo requires for the change.

Then, in one sentence, offer to work through the items. Do not start on any of
them, do not run `done`, and do not change the tracker.
