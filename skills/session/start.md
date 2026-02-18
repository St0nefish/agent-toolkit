---
description: >-
  Start a tracked development session. Use when beginning focused work on a
  feature, bug fix, or task. Creates a timestamped session file capturing goals,
  branch state, and starting context. Use /session:end to close.
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

# Start a Development Session

Create a session tracking file to capture goals, progress, and learnings.

## Steps

1. Ask the user what they're working on (goals for this session) if not already clear from context.

2. Gather current state by running the catchup script:

   ```bash
   ~/.claude/tools/session/bin/catchup
   ```

   This provides branch state, commits, changed files, uncommitted work, and session list — all in one call.

3. Create a session file at `.claude/sessions/<date>-<slug>.md` where:
   - `<date>` is today in `YYYY-MM-DD` format
   - `<slug>` is a short kebab-case summary of the goal (2-4 words)
   - Create the `.claude/sessions/` directory if it doesn't exist

4. Write the session file with this structure:

   ```markdown
   # Session: <brief title>

   **Started:** <ISO 8601 timestamp with timezone offset, e.g. 2026-02-17T09:30:00-05:00>
   **Branch:** <current branch>
   **Status:** active

   ## Goals

   - <goal 1>
   - <goal 2>

   ## Starting State

   - Recent commits: <last 3 commit subjects>
   - Working tree: <clean / N modified files>

   ## Progress

   <!-- Updated during the session -->

   ## Decisions

   <!-- Key decisions made and why -->

   ## Lessons

   <!-- Things learned, gotchas encountered -->
   ```

5. Confirm to the user that the session is being tracked and remind them to use `/session:end` when done.
