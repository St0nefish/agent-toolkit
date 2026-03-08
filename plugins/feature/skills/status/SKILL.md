---
name: status
description: >-
  Show a lightweight check of the current work context. Use when the user
  asks "what was I working on?", "do I have a session?", "session status",
  or comes back after a break and wants a reminder.
allowed-tools: Bash
---

Lightweight check of the current work context.

### Steps

1. Run catchup:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. From the output, extract and present a concise status card:

   ```
   Branch: <branch>
   Commits ahead of <default>: <N>
   Linked issue: #N — <title> (if branch matches type/NNN-*)
   Uncommitted changes: <none | N files>
   Recent commits: <last 3 subjects>
   ```

3. If the branch matches `type/NNN-*`, fetch just the issue title (no full body):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N> | jq -r '"#\(.number) — \(.title) [\(.state)]"'
   ```

4. **Do not read changed files or rebuild context.** This is intentionally lightweight. Point the user to `/feature resume` or `/feature catchup` for full context.
