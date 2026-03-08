---
description: "Rebuild full context of in-progress work"
allowed-tools: Bash, Read
---

Rebuild full context of in-progress work. Use after switching context or starting a new session.

### Steps

1. Run the catchup script:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup
   ```

2. If the current branch matches `type/NNN-*`, fetch the full issue and recent comments:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue show <N>
   ```

3. Read changed files (from both committed and uncommitted changes in the catchup output). If more than 15 files, prioritize:
   - Source code over generated/lock files
   - Files mentioned in recent commit messages
   - Test files alongside their implementations

4. Present a concise summary:
   - **Branch:** name and commits ahead of default
   - **Linked issue:** #N title, key requirements from body (if any)
   - **What's been done:** from recent commits
   - **What's in progress:** uncommitted changes, any WIP commit context
   - **Key files:** most important changed files
   - **Suggested next steps:** from issue, recent commits, or partial work

### Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to keep output lean
