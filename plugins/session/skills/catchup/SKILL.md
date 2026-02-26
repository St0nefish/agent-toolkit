---
name: session-catchup
description: >-
  Rebuild context on a branch you've been working on. Use when resuming work,
  switching back to a branch, or starting a new Claude session on in-progress
  work. Gathers branch state, changed files, and lists context files to read.
allowed-tools: Bash, Read
---

# Catch Up on Branch Context

Quickly rebuild understanding of in-progress work.

## Steps

1. Gather current state by running the catchup script:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   If a directory was provided, pass it as an argument: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup /path/to/dir`

2. After reviewing the output, use the Read tool selectively:
   - Plans — only read if resuming a specific planned effort
   - Most recent session file — for prior context and decisions
   - Do NOT re-read `.claude/todo.md` — already in the output above

3. Read changed files (committed + uncommitted). If more than 15, prioritize:
   - Source code over generated files
   - Files mentioned in commit messages
   - Test files alongside their implementations

4. Present a concise summary:
   - **Branch:** name and commits ahead
   - **What's been done:** from commits and session notes
   - **What's in progress:** uncommitted changes and open TODOs
   - **Key files:** most important changed files
   - **Suggested next steps:** from TODOs, session notes, or incomplete work

## Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to minimize token usage
