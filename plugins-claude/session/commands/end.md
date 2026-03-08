---
description: "Review, clean up, and open a PR to finalize the work"
allowed-tools: Bash, Read, AskUserQuestion, Task
---

Finalize the work: review, clean up commits, push, and open a PR.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Check for uncommitted work. If found, ask the user via AskUserQuestion:
   - **Commit it** — stage and commit before proceeding
   - **Discard it** — `git restore .`
   - **Cancel** — abort the `end` flow

3. **Agent review** — use the Task tool to spawn a review agent with this prompt:

   > Review the changes on the current branch compared to the default branch.
   > Focus on:
   > 1. Does the code actually address the linked issue (if any)?
   > 2. Code quality: clarity, edge cases, error handling
   > 3. Test coverage: are the changes tested?
   > 4. Any obvious bugs introduced?
   > Report findings concisely. Do not make changes — report only.

   Use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup` output and `git diff <default>..<branch>` as context for the review agent.

4. Present the review findings to the user. Ask via AskUserQuestion:
   - **Looks good, open PR** — proceed
   - **I'll fix the issues first** — pause the `end` flow; user will re-invoke when ready
   - **Open PR anyway** — skip fixes and proceed

5. Determine the linked issue number from the branch name (`type/NNN-*`). Build the PR body:

   ```markdown
   ## Summary

   <2-3 sentence description of what was done>

   ## Changes

   - <bulleted list of key changes>

   ## Testing

   <how this was tested or why no tests were needed>
   ```

   If a linked issue exists, append `Resolves #N` to the summary.

6. Create the PR:

   ```bash
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli repo default-branch)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   cat > /tmp/pr-body.md << 'EOF'
   <PR body from step 5>
   EOF
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli pr create \
     --title "<concise PR title>" \
     --head "$BRANCH" \
     --base "$DEFAULT" \
     --body-file /tmp/pr-body.md
   rm -f /tmp/pr-body.md
   ```

7. Confirm to the user: PR URL, linked issue (if any), and a reminder that CI/merge happens via the PR from here.

### Notes

- Do NOT open the PR earlier — PR creation triggers CI and merge pipelines
- WIP commits in the branch are fine; squashing is optional (not forced)
