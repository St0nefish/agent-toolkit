---
description: "Push work and record handoff context for cross-machine pickup"
allowed-tools: Bash, AskUserQuestion
---

Commit all work, push, and record handoff context on the linked issue for cross-machine pickup.

### Steps

1. Gather current state:
   inspect the current branch, default branch, recent commits, changed files,
   and any linked issue directly with `git` and native host tooling.

2. Based on the repo state and conversation context, construct the handoff content:

   **WIP commit body** (what changed — lives in git history):

   ```text
   === IN PROGRESS ===
   - <current state of work, partial implementations, files touched>
   ```

   **Issue comment** (what to do next — lives on the issue, accessible without cloning):

   ```text
   === HANDOFF ===
   Branch: <branch>
   Timestamp: <ISO 8601>
   From: <hostname>

   === NEXT STEPS ===
   - <ordered list of what to tackle on the other machine>

   === KEY CONTEXT ===
   - <decisions made, gotchas, environment details, important state>
   ```

3. Create the WIP commit:
   build a normal git commit that captures the in-progress summary in both the
   subject and body. Include:
   - branch name
   - UTC timestamp
   - host name
   - the `=== IN PROGRESS ===` section
   - the staged file list

   Substitute all template values with actual content before executing.

4. If the current branch matches `type/NNN-*`, post the handoff comment to the linked issue:
   - on GitHub repos, prefer `gh issue comment <N>` with the handoff body from step 2
   - otherwise use the equivalent host-native issue-comment command if available
   - use stdin or a heredoc rather than relying on plugin helper-script paths

5. Before running `git push`, confirm the user wants the branch published if they
   have not already approved pushing in this session.

6. Confirm to the user:
   - Branch pushed
   - Issue #N updated with handoff context (if applicable)
   - How to resume: `git pull && /session:resume` on the other machine

### Notes

- The WIP commit is a normal commit — continue working on top of it, no soft-reset needed
- If no issue is linked, context lives only in the WIP commit; instruct the user to run `/session:resume` on the other machine
