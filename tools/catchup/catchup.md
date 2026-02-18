---
description: >-
  Rebuild context on a branch you've been working on. Use when resuming work,
  switching back to a branch, or starting a new Claude session on in-progress
  work. Reads all changed files and recent session notes to get up to speed.
---

# Catch Up on Branch Context

Quickly rebuild understanding of in-progress work by reading what changed and any session notes.

## Steps

1. Identify the base branch and gather the diff:
   ```bash
   git rev-parse --abbrev-ref HEAD
   git log --oneline main..HEAD 2>/dev/null || git log --oneline master..HEAD 2>/dev/null
   ```

2. Get the list of changed files:
   ```bash
   git diff --name-only main..HEAD 2>/dev/null || git diff --name-only master..HEAD 2>/dev/null
   ```
   Also check for uncommitted work:
   ```bash
   git diff --name-only
   git diff --name-only --cached
   ```

3. If a `.claude/sessions/` directory exists, read the most recent session file for prior context:
   ```bash
   ls -t .claude/sessions/*.md 2>/dev/null | head -1
   ```

4. Read all changed files (committed + uncommitted). If there are more than 15 changed files, prioritize:
   - Source code over generated files
   - Files mentioned in recent commit messages
   - Test files alongside their implementation files

5. Present a concise summary to the user:
   - **Branch:** name and how many commits ahead of main
   - **What's been done:** based on commit messages and session notes
   - **What's in progress:** uncommitted changes
   - **Key files:** the most important changed files and what they do
   - **Suggested next steps:** based on session notes, TODOs, or incomplete work
