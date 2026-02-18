---
description: >-
  Save a checkpoint in the active session for continuing across context windows.
  Use when context is getting long, before a complex subtask, or when you want
  to preserve state before compaction. Manual only — invoke with /session:checkpoint.
---

# Checkpoint a Development Session

Append a checkpoint to the active session file to preserve state across context windows.

## Steps

1. Find the active session file:
   ```bash
   ls -t .claude/sessions/*.md 2>/dev/null | head -5
   ```
   Read the most recent one (or whichever has `**Status:** active`). If no active session is found, tell the user to start one with `/session:start`.

2. Gather current state:
   ```bash
   git status --short
   git log --oneline -5
   ```

3. Ask the user what's in progress and what should be picked up next — or infer from conversation context if it's clear.

4. Determine the checkpoint number by counting existing `## Checkpoint` headings in the session file (first checkpoint is 1).

5. Append a checkpoint section to the session file:
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

6. Confirm the checkpoint was saved. Remind the user to use `/session:resume` in a new context window to pick up where they left off.
