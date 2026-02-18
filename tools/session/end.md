---
description: >-
  End a tracked development session. Use when finishing work or wrapping up for
  the day. Summarizes what was accomplished, captures git changes, decisions,
  and lessons learned. Pairs with /session:start.
---

# End a Development Session

Close out the active session file with a summary of what happened.

## Steps

1. Find the most recent active session file:
   ```bash
   ls -t .claude/sessions/*.md 2>/dev/null | head -5
   ```
   Read the most recent one (or whichever has `**Status:** active`). If no active session file is found, summarize the current session directly to the user without writing a file.

2. Gather what changed during the session:
   ```bash
   ~/.claude/tools/session/bin/catchup
   ```
   This provides branch state, commits, changed files, and uncommitted work in one call.

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
