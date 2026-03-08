---
description: "Show a quick summary of the active feature session"
allowed-tools: Bash, Read
---

Quick check for an active session with a brief summary of what's in progress.

## Steps

1. Run catchup with active session content:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup --active-session
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
   **Handoff pending** from <hostname> — use `/feature:resume` to pick up where you left off.
   ```

   End with a suggestion:
   - If the session has checkpoints with next steps: "Use `/feature:resume` to rebuild full context and continue."
   - If the session is fresh (no checkpoints): "You can continue working, or `/feature:end` to close it."

   ### No active session

   Check the `=== SESSIONS ===` section for recent completed sessions. If any exist, mention the most recent one:

   ```
   No active session. Last session: "<title>" (<date>, completed).
   Use `/feature:start` to begin a new session.
   ```

   If no sessions exist at all:

   ```
   No sessions found. Use `/feature:start` to begin tracking your work.
   ```

3. **Do NOT read changed files or rebuild context.** This is intentionally lightweight — just report status. Point the user to `/feature:resume` or `/feature:catchup` if they want full context.
