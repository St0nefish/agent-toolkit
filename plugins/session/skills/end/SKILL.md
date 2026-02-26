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
   BASE=$(git rev-parse --verify main 2>/dev/null && echo main || git rev-parse --verify master 2>/dev/null && echo master || echo "")
   BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
   echo "=== BRANCH ==="; echo "current: $BRANCH"
   if [ -n "$BASE" ] && [ "$BRANCH" != "$BASE" ]; then
     echo "ahead: $(git rev-list --count "$BASE..HEAD") commits"
     echo ""; echo "=== BRANCH COMMITS ==="; git log --oneline "$BASE..HEAD"
   fi
   STAGED=$(git diff --name-only --cached); UNSTAGED=$(git diff --name-only)
   if [ -n "$STAGED$UNSTAGED" ]; then
     echo ""; echo "=== UNCOMMITTED ==="
     [ -n "$STAGED" ] && echo "staged:" && echo "$STAGED"
     [ -n "$UNSTAGED" ] && echo "unstaged:" && echo "$UNSTAGED"
   fi
   ACTIVE=$(find .claude/sessions -name "*.md" -exec grep -l "Status.*active" {} \; 2>/dev/null | sort -r | head -1)
   if [ -n "$ACTIVE" ]; then
     echo ""; echo "=== ACTIVE SESSION ==="; echo "file: $ACTIVE"; echo ""; cat "$ACTIVE"
   else
     echo ""; echo "=== SESSIONS ==="; ls -t .claude/sessions/*.md 2>/dev/null || echo "(none)"
   fi
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
