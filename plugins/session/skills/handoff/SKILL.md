---
name: session-handoff
description: >-
  Hand off work to another machine via a WIP commit. Use when you need to
  continue work on a different computer. Stages all changes, creates a
  structured WIP commit with handoff context, and pushes. Invoke with
  /session-handoff.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

# Hand Off Work to Another Machine

Create a WIP commit with structured context and push for cross-machine transfer.

## Steps

1. Gather current state:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   Review the branch state, uncommitted changes, and session context.

2. **Checkpoint the active session** (if one exists). From the `=== ACTIVE SESSION ===` output, append a checkpoint section to the session file using the same format as `/session-checkpoint` — this preserves context locally since session files are gitignored and won't be in the handoff commit.

3. Based on the catchup output and conversation context, construct a structured handoff message with these sections:

   ```
   === IN PROGRESS ===
   - <current state of work, what's partially done>

   === NEXT STEPS ===
   - <what to pick up on the other machine>

   === KEY CONTEXT ===
   - <decisions made, gotchas, important state>
   ```

4. Run the handoff script with the message:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/handoff -m "<structured message>"
   ```

   This stages all changes (`git add -A`), creates a WIP commit, and pushes to remote.

5. Confirm to the user:
   - Branch name and that it was pushed
   - How to resume on the other machine: `git pull && /session-resume` or `/catchup`
   - The WIP commit context will appear in BRANCH COMMITS when catchup runs on the other machine

## Exit Codes

- **0** — success (committed and pushed)
- **1** — bad usage (missing -m flag)
- **2** — not a git repository
- **3** — nothing to commit (clean working tree)
- **4** — push failed (commit exists locally, push manually)

## Notes

- The WIP commit is a normal commit — continue working on top of it
- Next real commit naturally follows the WIP, no soft-reset needed
- If push fails, the commit still exists locally; push manually with `git push`
