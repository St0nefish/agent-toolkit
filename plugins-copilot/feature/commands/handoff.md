---
description: "Create a WIP commit with structured context and push for cross-machine transfer"
allowed-tools: Bash, Read, Edit
---

Create a WIP commit with structured context and push for cross-machine transfer.

## Steps

1. Gather current state:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   Review the branch state, uncommitted changes, and session context.

2. **Checkpoint the active session** (if one exists). From the `=== ACTIVE SESSION ===` output, append a checkpoint section to the session file using the same format as `/feature:checkpoint` — this preserves context locally since session files are gitignored and won't be in the handoff commit.

3. Based on the catchup output and conversation context, construct a structured handoff message with these sections:

   ```
   === IN PROGRESS ===
   - <current state of work, what's partially done>

   === NEXT STEPS ===
   - <what to pick up on the other machine>

   === KEY CONTEXT ===
   - <decisions made, gotchas, important state>
   ```

4. Create the WIP commit and push:

   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")
   git add -A
   git commit --no-verify -m "WIP: <first line of IN PROGRESS>

=== HANDOFF ===
Branch: $BRANCH
Timestamp: $TIMESTAMP
From: $HOSTNAME

<full structured message>

=== FILES IN THIS COMMIT ===
$(git diff --cached --name-only)"
   git push

   ```

   Substitute the actual handoff message content into the commit body before running. If `git push` fails, the commit still exists locally — tell the user to `git push` manually.

5. Confirm to the user:
   - Branch name and that it was pushed
   - How to resume on the other machine: `git pull && /feature:resume` or `/feature:catchup`
   - The WIP commit context will appear in BRANCH COMMITS when catchup runs on the other machine

## Notes

- The WIP commit is a normal commit — continue working on top of it
- Next real commit naturally follows the WIP, no soft-reset needed
- If push fails, the commit still exists locally; push manually with `git push`
