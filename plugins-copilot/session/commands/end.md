---
description: "Review, clean up, and open a PR to finalize the work"
allowed-tools: Bash, Read, AskUserQuestion, Task
---

Finalize the work: review, clean up commits, push, open a PR, watch CI, and return to the default branch.

### Steps

1. Gather current state:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup
   ```

   Extract from the output:
   - `CURRENT` — the current branch name
   - `DEFAULT` — the default branch name (e.g. `master` or `main`)
   - `ON_BASE` — true if the current branch IS the default branch with no diverging commits

   If `ON_BASE` is true and there are no uncommitted changes, tell the user there is nothing to finalize and stop.

2. Check for uncommitted work. If found, ask the user via AskUserQuestion:
   - **Commit it** — stage and commit before proceeding
   - **Discard it** — `git restore .`
   - **Cancel** — abort the `end` flow

   If `ON_BASE` is true (working directly on the default branch), push the commit and skip to step 8 (CI watch). Steps 3-7 only apply to feature branches.

3. **Agent review** — use the Task tool to spawn a review agent with this prompt:

   > Review the changes on the current branch compared to the default branch.
   > Focus on:
   > 1. Does the code actually address the linked issue (if any)?
   > 2. Code quality: clarity, edge cases, error handling
   > 3. Test coverage: are the changes tested?
   > 4. Any obvious bugs introduced?
   > Report findings concisely. Do not make changes — report only.

   Use `bash ${COPILOT_PLUGIN_ROOT}/scripts/catchup` output and `git diff <default>..<branch>` as context for the review agent.

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
   DEFAULT=$(bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli repo default-branch)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   cat > /tmp/pr-body.md << 'EOF'
   <PR body from step 5>
   EOF
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli pr create \
     --title "<concise PR title>" \
     --head "$BRANCH" \
     --base "$DEFAULT" \
     --body-file /tmp/pr-body.md
   rm -f /tmp/pr-body.md
   ```

7. Confirm to the user: PR URL, linked issue (if any), and note that CI is being watched next.

8. **Watch CI** — poll the CI run for the current branch:

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/git-cli run watch --branch "$BRANCH"
   ```

   Parse the key:value stdout output (`status`, `url`, `duration`, `failed_jobs`). Then:
   - **`pass`** — continue to step 9
   - **`fail`** — show the failed jobs and log excerpt (printed to stderr by `run watch`). Ask via AskUserQuestion:
     - **Fix it** — pause the `end` flow; user will address failures and re-invoke
     - **Ignore** — continue to step 9
   - **`no-workflow`** — note that no CI workflow was found; continue to step 9
   - **`timeout`** — ask via AskUserQuestion:
     - **Wait longer** — re-run `run watch` with `--initial-delay 0` and a longer `--timeout`
     - **Continue** — proceed to step 9

9. **Return to default branch:**

   ```bash
   bash ${COPILOT_PLUGIN_ROOT}/scripts/branch default && git pull
   ```

   Skip if already on the default branch.

10. **Final summary** — present to the user:
    - PR URL (if created)
    - CI status (pass/fail/no-workflow/timeout)
    - Current branch (should be the default branch now)
    - Linked issue (if any)

### Notes

- Do NOT open the PR earlier — PR creation triggers CI and merge pipelines
- WIP commits in the branch are fine; squashing is optional (not forced)
