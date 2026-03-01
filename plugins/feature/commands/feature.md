---
description: "Feature tracking — start, end, checkpoint, status, catchup, handoff, resume"
argument-hint: "[action]"
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
disable-model-invocation: true
---

# Feature Tracking

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `end`, `checkpoint`, `status`, `catchup`, `handoff`, `resume`. Usage: `/feature [action]`)

---

## start

Create a session tracking file to capture goals, progress, and learnings.

### Steps

1. **Gather current state** by running the catchup script:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   This provides branch state, commits, changed files, uncommitted work, todo list, session list, and handoff detection — all in one call.

2. **Check for handoff.** If the output contains `=== LATEST HANDOFF ===`, a WIP handoff commit is pending. Use AskUserQuestion to ask:
   - **Continue handoff work** — resume the handed-off task (briefly describe the IN PROGRESS items)
   - **Start something new** — ignore the handoff and pick a new task

   If they choose to continue the handoff, extract the goal from the handoff's IN PROGRESS/NEXT STEPS and skip to step 4.

3. **What to work on?** Skip this step if the user provided a prompt/goal when invoking the command.

   Use the `=== TODO ===` section from the catchup output (do NOT re-read `.claude/todo.md`). If it has unchecked (`- [ ]`) items, display them as a numbered list grouped by section heading, then end with:

   > Type a number, or describe what you want to work on:

   If `.claude/todo.md` doesn't exist or has no unchecked items, just ask:

   > What do you want to work on?

   Then STOP and wait for the user's reply. Do not call any tools. Do not continue to step 4. The user will type a number or a description — match it to a TODO item or use it as-is, then continue to step 4.

4. Create a session file at `.claude/sessions/<date>-<slug>.md` where:
   - `<date>` is today in `YYYY-MM-DD` format
   - `<slug>` is a short kebab-case summary of the goal (2-4 words)
   - Create the `.claude/sessions/` directory if it doesn't exist

5. Write the session file with this structure:

   ```markdown
   # Session: <brief title>

   **Started:** <ISO 8601 timestamp with timezone offset, e.g. 2026-02-17T09:30:00-05:00>
   **Branch:** <current branch>
   **Status:** active

   ## Goals

   - <goal 1>
   - <goal 2>

   ## Starting State

   - Recent commits: <last 3 commit subjects>
   - Working tree: <clean / N modified files>

   ## Progress

   <!-- Updated during the session -->

   ## Decisions

   <!-- Key decisions made and why -->

   ## Lessons

   <!-- Things learned, gotchas encountered -->
   ```

6. Confirm to the user that the session is being tracked and remind them to use `/feature end` when done.

---

## end

Close out the active session file with a summary of what happened.

### Steps

1. Gather session state and active session content in one call:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
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

---

## checkpoint

PROACTIVELY invoke this (without being asked) after completing a major task, stage, or milestone, or when context window usage is approaching full.

Append a checkpoint to the active session file to preserve state across context windows.

### Steps

1. Gather state and active session content in one call:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   This provides branch state, commits, uncommitted work, and the full content of the active session file — all in one call.

2. From the output, find the `=== ACTIVE SESSION ===` section which contains the session file path and content. If no active session is found, tell the user to start one with `/feature start`.

3. Infer what's in progress and what should be picked up next from conversation context. When auto-triggering (not user-invoked), do NOT ask — infer from the conversation. Only use AskUserQuestion if the user explicitly invoked `/feature checkpoint` and progress is genuinely unclear.

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

6. Briefly confirm the checkpoint was saved. When auto-triggering, keep confirmation minimal (one line) so it doesn't interrupt the workflow. When user-invoked, remind them to use `/feature resume` in a new context window to pick up where they left off.

---

## status

Quick check for an active session with a brief summary of what's in progress.

### Steps

1. Run catchup with active session content:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
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
   **Handoff pending** from <hostname> — use `/feature resume` to pick up where you left off.
   ```

   End with a suggestion:
   - If the session has checkpoints with next steps: "Use `/feature resume` to rebuild full context and continue."
   - If the session is fresh (no checkpoints): "You can continue working, or `/feature end` to close it."

   ### No active session

   Check the `=== SESSIONS ===` section for recent completed sessions. If any exist, mention the most recent one:

   ```
   No active session. Last session: "<title>" (<date>, completed).
   Use `/feature start` to begin a new session.
   ```

   If no sessions exist at all:

   ```
   No sessions found. Use `/feature start` to begin tracking your work.
   ```

3. **Do NOT read changed files or rebuild context.** This is intentionally lightweight — just report status. Point the user to `/feature resume` or `/feature catchup` if they want full context.

---

## catchup

Quickly rebuild understanding of in-progress work.

### Steps

1. Gather current state by running the catchup script:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   If a directory was provided, pass it as an argument: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup /path/to/dir`

2. After reviewing the output, use the Read tool selectively:
   - Plans — only read if resuming a specific planned effort
   - Most recent session file — for prior context and decisions
   - Do NOT re-read `.claude/todo.md` — already in the output above

3. Read changed files (committed + uncommitted). If more than 15, prioritize:
   - Source code over generated files
   - Files mentioned in commit messages
   - Test files alongside their implementations

4. Present a concise summary:
   - **Branch:** name and commits ahead
   - **What's been done:** from commits and session notes
   - **What's in progress:** uncommitted changes and open TODOs
   - **Key files:** most important changed files
   - **Suggested next steps:** from TODOs, session notes, or incomplete work

### Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to minimize token usage

---

## handoff

Create a WIP commit with structured context and push for cross-machine transfer.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   Review the branch state, uncommitted changes, and session context.

2. **Checkpoint the active session** (if one exists). From the `=== ACTIVE SESSION ===` output, append a checkpoint section to the session file using the same format as the checkpoint action — this preserves context locally since session files are gitignored and won't be in the handoff commit.

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
   - How to resume on the other machine: `git pull && /feature resume` or `/feature catchup`
   - The WIP commit context will appear in BRANCH COMMITS when catchup runs on the other machine

### Notes

- The WIP commit is a normal commit — continue working on top of it
- Next real commit naturally follows the WIP, no soft-reset needed
- If push fails, the commit still exists locally; push manually with `git push`

---

## resume

Rebuild context from an active session, checkpoint, or handoff.

### Steps

1. Run catchup with active session content:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup --active-session
   ```

   This provides branch state, commits, changed files, uncommitted work, the active session file content, and handoff detection — all in one call.

1. **Detect the resume mode** from the output. Check for two signals:
   - **Handoff?** — `=== LATEST HANDOFF ===` section is present (HEAD commit is a WIP handoff)
   - **Active session?** — `=== ACTIVE SESSION ===` section is present with checkpoint(s)

2. **Branch on what's found:**

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
   - Or suggest `/feature catchup` if they just want branch context without session tracking

3. Present a combined summary to the user:
   - **Branch state** — current branch, commits ahead, uncommitted changes
   - **Resume source** — "handoff from <hostname>" or "checkpoint <n>"
   - **What's in progress** — from handoff or checkpoint
   - **Next steps** — from handoff or checkpoint
   - **Key context** — decisions, gotchas, important state
   - **Suggested action** — continue from next steps

4. Ask the user if they want to proceed with the next steps or adjust the plan.
