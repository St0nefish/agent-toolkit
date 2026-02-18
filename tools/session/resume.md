---
description: >-
  Resume a session in a new context window. Runs catchup for git state, reads
  the latest checkpoint from the active session, and presents combined context.
  Use when starting a new Claude session to continue previous work.
---

# Resume a Development Session

Rebuild context from an active session and its latest checkpoint.

## Steps

1. Run catchup to gather git state:
   ```bash
   ~/.claude/tools/session/bin/catchup
   ```

2. From the catchup output, identify session files. Look for any marked `(active)`. If none are active, list recent sessions and ask the user which to resume.

3. Read the active session file. Extract:
   - Session goals (from `## Goals`)
   - The latest `## Checkpoint` section (highest numbered)
   - Any `## Decisions` and `## Lessons` already recorded

4. Read changed files that are most relevant — prioritize files mentioned in the checkpoint's "In Progress" and "Next Steps" sections.

5. Present a combined summary to the user:
   - **Branch state** — current branch, commits ahead, uncommitted changes (from catchup)
   - **Session goals** — what this session set out to do
   - **Last checkpoint** — completed items, in-progress work, next steps, key context
   - **Uncommitted changes** — files with pending modifications
   - **Suggested action** — continue from the checkpoint's "Next Steps"

6. Ask the user if they want to proceed with the next steps or adjust the plan.
