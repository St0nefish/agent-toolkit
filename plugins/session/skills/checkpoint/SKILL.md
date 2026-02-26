---
name: session-checkpoint
description: >-
  Save a checkpoint in the active session to preserve progress across context
  windows. Triggers after completing a major task, stage, or milestone, or
  when context window usage is approaching full. Also available via
  /session-checkpoint.
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# Checkpoint a Development Session

PROACTIVELY invoke this (without being asked) after completing a major task, stage, or milestone, or when context window usage is approaching full.

Append a checkpoint to the active session file to preserve state across context windows.

## Steps

1. Gather state and active session content in one call:

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

   This provides branch state, commits, uncommitted work, and the full content of the active session file — all in one call.

2. From the output, find the `=== ACTIVE SESSION ===` section which contains the session file path and content. If no active session is found, tell the user to start one with `/session-start`.

3. Infer what's in progress and what should be picked up next from conversation context. When auto-triggering (not user-invoked), do NOT ask — infer from the conversation. Only use AskUserQuestion if the user explicitly invoked `/session-checkpoint` and progress is genuinely unclear.

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

6. Briefly confirm the checkpoint was saved. When auto-triggering, keep confirmation minimal (one line) so it doesn't interrupt the workflow. When user-invoked, remind them to use `/session-resume` in a new context window to pick up where they left off.
