---
description: >-
  End a tracked development session. Use when finishing work or wrapping up for
  the day. Summarizes what was accomplished, captures git changes, decisions,
  and lessons learned. Pairs with /session:start.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

# End a Development Session

Close out the active session file with a summary of what happened.

## Steps

1. Gather session state and what changed:

   ```bash
   ~/.claude/tools/session/bin/catchup
   ```

   This provides branch state, commits, changed files, uncommitted work, and lists session files with `(active)` markers — all in one call.

2. From the `=== SESSIONS ===` section of catchup output, identify the active session file (marked with `(active)`). Read it. If no active session file is found, summarize the current session directly to the user without writing a file.

3. Update the session file:

   - Change `**Status:** active` to `**Status:** completed`
   - Add `**Ended:** <ISO 8601 timestamp>`
   - Fill in the **Progress** section with a bulleted list of what was done (commits, files changed, features added/fixed)
   - Fill in the **Decisions** section with any notable choices made and their rationale
   - Fill in the **Lessons** section with gotchas, debugging insights, or patterns discovered
   - Add a **Summary** section at the end with a 1-2 sentence wrap-up

4. Present the summary to the user — keep it concise:
   - Duration
   - Commits made
   - Key accomplishments
   - Any open items or next steps
