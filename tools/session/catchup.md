---
description: >-
  Rebuild context on a branch you've been working on. Use when resuming work,
  switching back to a branch, or starting a new Claude session on in-progress
  work. Gathers branch state, changed files, and lists context files to read.
---

# Catch Up on Branch Context

Quickly rebuild understanding of in-progress work.

## Steps

1. Run the catchup script:
   ```bash
   ~/.claude/tools/session/bin/catchup
   ```
   Or pass a directory:
   ```bash
   ~/.claude/tools/session/bin/catchup /path/to/repo
   ```

2. The script outputs only sections with content:
   - **BRANCH** — current branch, base branch, commits ahead
   - **BRANCH COMMITS** — commits on feature branch (omitted on base)
   - **RECENT COMMITS** — last 10 commits (only shown on base branch)
   - **CHANGED FILES** — files changed vs base (only on feature branches)
   - **UNCOMMITTED** — staged, unstaged, untracked (omitted if clean)
   - **TODO** — full contents of `.claude/todo.md` (always included if present)
   - **PLANS** — lists `.claude/plans/*.md` paths (not contents)
   - **SESSIONS** — lists `.claude/sessions/*.md` paths, with `(active)` annotation

3. After reviewing script output, use the Read tool selectively:
   - Plans — only read if resuming a specific planned effort
   - Most recent session file — for prior context and decisions
   - Do NOT read `.claude/todo.md` — its contents are already in the output

4. Read changed files (committed + uncommitted). If more than 15, prioritize:
   - Source code over generated files
   - Files mentioned in commit messages
   - Test files alongside their implementations

5. Present a concise summary:
   - **Branch:** name and commits ahead
   - **What's been done:** from commits and session notes
   - **What's in progress:** uncommitted changes and open TODOs
   - **Key files:** most important changed files
   - **Suggested next steps:** from TODOs, session notes, or incomplete work

## Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to minimize token usage
