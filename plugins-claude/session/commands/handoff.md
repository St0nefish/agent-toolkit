---
description: "Push work and record handoff context for cross-machine pickup"
allowed-tools: Bash, AskUserQuestion
---

Commit all work, push, and record handoff context on the linked issue for cross-machine pickup.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Based on catchup output and conversation context, construct the handoff content:

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

=== IN PROGRESS ===
<in-progress content>

=== FILES IN THIS COMMIT ===
$(git diff --cached --name-only)"
   git push

   ```text

   Substitute all template values with actual content before executing. If `git push` fails, the commit still exists locally — inform the user to push manually.

4. If the current branch matches `type/NNN-*`, post the handoff comment to the linked issue:

```

   ```bash
   cat > /tmp/handoff-comment.md << 'EOF'
   <issue comment content from step 2>
   EOF
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli issue comment <N> --body-file /tmp/handoff-comment.md
   rm -f /tmp/handoff-comment.md
   ```

5. Confirm to the user:
   - Branch pushed
   - Issue #N updated with handoff context (if applicable)
   - How to resume: `git pull && /session:resume` on the other machine

### Notes

- The WIP commit is a normal commit — continue working on top of it, no soft-reset needed
- If no issue is linked, context lives only in the WIP commit; instruct the user to run `/session:resume` on the other machine
