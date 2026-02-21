---
name: session-resume
description: >-
  Resume a session in a new context window. Runs catchup for git state, reads
  the latest checkpoint from the active session, and presents combined context.
  Use when starting a new Claude session to continue previous work.
allowed-tools: Bash, Read, AskUserQuestion
---

# Resume a Development Session

Rebuild context from an active session, checkpoint, or handoff.

## Steps

1. Run catchup with active session content:

   ```bash
   ~/.claude/tools/session/bin/catchup --active-session
   ```

   This provides branch state, commits, changed files, uncommitted work, the active session file content, and handoff detection — all in one call.

2. **Detect the resume mode** from the output. Check for two signals:
   - **Handoff?** — `=== LATEST HANDOFF ===` section is present (HEAD commit is a WIP handoff)
   - **Active session?** — `=== ACTIVE SESSION ===` section is present with checkpoint(s)

3. **Branch on what's found:**

   ### Both handoff and active session

   Ask the user which context to resume from:
   - **Handoff** — continue from the WIP commit pushed from another machine
   - **Session checkpoint** — continue from the latest checkpoint in the active session

   Briefly describe what each contains (handoff's "From" host and first IN PROGRESS item, checkpoint number and its first "Next Steps" item) so the user can make an informed choice. Then follow the appropriate path below.

   ### Handoff only

   The `=== LATEST HANDOFF ===` section contains the full WIP commit message with structured context from another machine.

   - Extract **IN PROGRESS**, **NEXT STEPS**, **KEY CONTEXT**, and **FILES IN THIS COMMIT** from the handoff section
   - Read the files listed in FILES IN THIS COMMIT to understand the WIP changes
   - Continue working on top of the WIP commit — no soft-reset needed

   ### Session only

   - From the `=== ACTIVE SESSION ===` content, extract:
     - Session goals (from `## Goals`)
     - The latest `## Checkpoint` section (highest numbered)
     - Any `## Decisions` and `## Lessons` already recorded
   - Read changed files that are most relevant — prioritize files mentioned in the checkpoint's "In Progress" and "Next Steps"

   ### Neither

   - List recent sessions from `=== SESSIONS ===` and ask the user which to resume
   - Or suggest `/catchup` if they just want branch context without session tracking

4. Present a combined summary to the user:
   - **Branch state** — current branch, commits ahead, uncommitted changes
   - **Resume source** — "handoff from <hostname>" or "checkpoint <n>"
   - **What's in progress** — from handoff or checkpoint
   - **Next steps** — from handoff or checkpoint
   - **Key context** — decisions, gotchas, important state
   - **Suggested action** — continue from next steps

5. Ask the user if they want to proceed with the next steps or adjust the plan.
