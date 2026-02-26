---
name: session-status
description: >-
  Check if a development session is active and show a quick summary.
  Use when the user asks "what was I working on?", "do I have a session?",
  "session status", or comes back after a break and wants a reminder.
  Lighter than /session-resume — just a status check, no full context rebuild.
allowed-tools: Bash, Read
---

# Session Status

Quick check for an active session with a brief summary of what's in progress.

## Steps

1. Run catchup with active session content:

   ```bash
   BASE=$(git rev-parse --verify main 2>/dev/null && echo main || git rev-parse --verify master 2>/dev/null && echo master || echo "")
   BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
   echo "=== BRANCH ==="; echo "current: $BRANCH"
   if [ -n "$BASE" ] && [ "$BRANCH" != "$BASE" ]; then
     echo "ahead: $(git rev-list --count "$BASE..HEAD") commits"
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
     echo ""; echo "=== SESSIONS ==="; ls -t .claude/sessions/*.md 2>/dev/null | head -5 || echo "(none)"
   fi
   ```

2. **Check for an active session** in the output:

   ### Active session found (`=== ACTIVE SESSION ===` present)

   Extract from the session content:
   - **Session title** (from the `# Session:` heading)
   - **Started** timestamp
   - **Branch**
   - **Goals** (from `## Goals`)
   - **Latest checkpoint** — if any `## Checkpoint` sections exist, extract the most recent one's Completed / In Progress / Next Steps
   - If no checkpoints, note what progress has been recorded under `## Progress`

   Also note from the catchup output:
   - **Uncommitted changes** — from `=== UNCOMMITTED ===` if present
   - **Handoff pending** — if `=== LATEST HANDOFF ===` is present

   Present a concise status card:

   ```
   **Session:** <title>
   **Started:** <relative time, e.g. "2 hours ago" or "yesterday">
   **Branch:** <branch>
   **Goals:** <bulleted list>

   **Current state:** <summary from latest checkpoint or progress>
   ```

   If there's a handoff, add:

   ```
   **Handoff pending** from <hostname> — use `/session-resume` to pick up where you left off.
   ```

   End with a suggestion:
   - If the session has checkpoints with next steps: "Use `/session-resume` to rebuild full context and continue."
   - If the session is fresh (no checkpoints): "You can continue working, or `/session-end` to close it."

   ### No active session

   Check the `=== SESSIONS ===` section for recent completed sessions. If any exist, mention the most recent one:

   ```
   No active session. Last session: "<title>" (<date>, completed).
   Use `/session-start` to begin a new session.
   ```

   If no sessions exist at all:

   ```
   No sessions found. Use `/session-start` to begin tracking your work.
   ```

3. **Do NOT read changed files or rebuild context.** This skill is intentionally lightweight — just report status. Point the user to `/session-resume` or `/catchup` if they want full context.
