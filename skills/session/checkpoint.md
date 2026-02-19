---
description: >-
  Save a checkpoint in the active session for continuing across context windows.
  Use when context is getting long, before a complex subtask, or when you want
  to preserve state before compaction. Invoke with /session-checkpoint.
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# Checkpoint a Development Session

Append a checkpoint to the active session file to preserve state across context windows.

## Steps

1. Gather state and active session content in one call:

   ```bash
   ~/.claude/tools/session/bin/catchup --active-session
   ```

   This provides branch state, commits, changed files, uncommitted work, and the full content of the active session file — all in one call.

2. From the output, find the `=== ACTIVE SESSION ===` section which contains the session file path and content. If no active session is found, tell the user to start one with `/session-start`.

3. Infer what's in progress and what should be picked up next from conversation context. If unclear, use AskUserQuestion to ask what's in progress and what to pick up next.

4. Determine the checkpoint number by counting existing `## Checkpoint` headings in the session content (first checkpoint is 1).

5. Append a checkpoint section to the session file using Edit:

   ```markdown
   ## Checkpoint <n> — <ISO 8601 timestamp with timezone offset>

   ### Completed
   - <what's been done since last checkpoint or session start>

   ### In Progress
   - <current state of work, partial implementations>

   ### Next Steps
   - <what to pick up in the next window>

   ### Key Context
   - <decisions, gotchas, important state that shouldn't be lost>
   ```

6. Confirm the checkpoint was saved. Remind the user to use `/session-resume` in a new context window to pick up where they left off.
