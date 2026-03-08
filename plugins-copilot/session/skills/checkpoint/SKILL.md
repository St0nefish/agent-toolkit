---
user-invocable: false
name: checkpoint
description: >-
  Save a checkpoint in the active session to preserve progress across context
  windows. Triggers after completing a major task, stage, or milestone, or
  when context window usage is approaching full.
allowed-tools: Bash, AskUserQuestion
---

PROACTIVELY invoke this (without being asked) after completing a major task, stage, or milestone, or when context window usage is approaching full.

Commits staged/unstaged changes and posts structured context to the linked issue.

### Steps

1. Gather current state:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup
   ```

2. Infer what's in progress and what should come next from conversation context. When auto-triggering, do NOT ask — infer from the conversation. Only use AskUserQuestion if explicitly invoked and progress is genuinely unclear.

3. Compose the checkpoint comment content with these sections:

   ```text
   === CHECKPOINT ===
   Branch: <branch>
   Timestamp: <ISO 8601>

   === NEXT STEPS ===
   - <what to pick up next>

   === KEY CONTEXT ===
   - <decisions, gotchas, important state that shouldn't be lost>
   ```

4. Commit any uncommitted changes:

   ```bash
   git add -A
   git commit --no-verify -m "checkpoint: <brief description of progress>"
   git push
   ```

   If there are no changes to commit, skip the commit step but still post the issue comment.

5. If the current branch matches `type/NNN-*`, post the checkpoint as an issue comment:

   ```bash
   cat > /tmp/checkpoint-comment.md << 'EOF'
   <checkpoint content from step 3>
   EOF
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli issue comment <N> --body-file /tmp/checkpoint-comment.md
   rm -f /tmp/checkpoint-comment.md
   ```

6. Briefly confirm: checkpoint committed and (if applicable) posted to issue #N. When auto-triggering, keep to one line. When user-invoked, mention `/session:resume` to continue from this point.
