---
description: >-
  Start a tracked development session. Use when beginning focused work on a
  feature, bug fix, or task. Creates a timestamped session file capturing goals,
  branch state, and starting context. Use /session-end to close.
disable-model-invocation: true
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Start a Development Session

Create a session tracking file to capture goals, progress, and learnings.

## Steps

1. **Gather current state** by running the catchup script:

   ```bash
   ~/.claude/tools/session/bin/catchup
   ```

   This provides branch state, commits, changed files, uncommitted work, session list, and handoff detection — all in one call.

2. **Check for handoff.** If the output contains `=== LATEST HANDOFF ===`, a WIP handoff commit is pending. Use AskUserQuestion to ask:
   - **Continue handoff work** — resume the handed-off task (briefly describe the IN PROGRESS items)
   - **Start something new** — ignore the handoff and pick a new task

   If they choose to continue the handoff, extract the goal from the handoff's IN PROGRESS/NEXT STEPS and skip to step 4.

3. **What to work on?** Skip this step if the user provided a prompt/goal when invoking the command.

   Use the `=== TODO ===` section from the catchup output (do NOT re-read `.claude/todo.md`). If it has unchecked (`- [ ]`) items, display them as a numbered list grouped by section heading, then end with:

   > Type a number, or describe what you want to work on:

   If `.claude/todo.md` doesn't exist or has no unchecked items, just ask:

   > What do you want to work on?

   Then STOP and wait for the user's reply. Do not call any tools. Do not continue to step 4. The user will type a number or a description — match it to a TODO item or use it as-is, then continue to step 4.

4. Create a session file at `.claude/sessions/<date>-<slug>.md` where:
   - `<date>` is today in `YYYY-MM-DD` format
   - `<slug>` is a short kebab-case summary of the goal (2-4 words)
   - Create the `.claude/sessions/` directory if it doesn't exist

5. Write the session file with this structure:

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

6. Confirm to the user that the session is being tracked and remind them to use `/session-end` when done.
