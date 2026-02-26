---
name: session-end
description: >-
  End a tracked development session. Use when finishing work or wrapping up for
  the day. Summarizes what was accomplished, captures git changes, decisions,
  and lessons learned. Pairs with /session-start.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# End a Development Session

Close out the active session file with a summary of what happened.

## Steps

1. Gather session state and active session content in one call:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   This provides branch state, commits, uncommitted work, session list, and the full content of the active session file — all in one call.

2. From the output, find the `=== ACTIVE SESSION ===` section which contains the session file path and content. If no active session is found, summarize the current session directly to the user without writing a file.

3. Update the session file:

   - Change `**Status:** active` to `**Status:** completed`
   - Add `**Ended:** <ISO 8601 timestamp>`
   - Fill in the **Progress** section with a bulleted list of what was done (commits, files changed, features added/fixed)
   - Fill in the **Decisions** section with any notable choices made and their rationale
   - Fill in the **Lessons** section with gotchas, debugging insights, or patterns discovered
   - Add a **Summary** section at the end with a 1-2 sentence wrap-up

4. Update `.claude/todo.md` if relevant:
   - Delete items that were completed during this session (code and git history are the record)
   - Add new items discovered during the session (bugs found, follow-up work identified, ideas worth investigating)
   - Skip this step if nothing changed

5. Present the summary to the user — keep it concise:
   - Duration
   - Commits made
   - Key accomplishments
   - Any open items or next steps

6. If there are uncommitted changes, use AskUserQuestion to ask if the user wants to:
   - **Commit and push** — stage, commit, and push the current work
   - **Commit only** — stage and commit without pushing
   - **Leave as-is** — keep changes uncommitted

   Session files (`.claude/sessions/`) are gitignored and never committed.
