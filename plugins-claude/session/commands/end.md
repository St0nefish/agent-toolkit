---
description: "Review, clean up, and open a PR to finalize the work"
allowed-tools: Bash, Read, AskUserQuestion, Task
---

Finalize the work: review, clean up commits, push, open a PR,
watch CI, and return to the default branch.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   Extract from the output:
   - `CURRENT` — the current branch name
   - `DEFAULT` — the default branch name
     (e.g. `master` or `main`)
   - `ON_BASE` — true if the current branch IS the
     default branch with no diverging commits

   If `ON_BASE` is true and there are no uncommitted
   changes, tell the user there is nothing to finalize
   and stop.

1b. Check for an existing open PR for the current branch:

   ```bash
   PR_JSON=$(bash \
     ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     pr list --state open \
     | jq --arg b "$CURRENT" \
       '.[] | select(.head == $b)')
   ```

   If found, extract the PR URL and number, skip
   steps 3-7, and jump directly to step 8 (CI watch)
   using the existing PR info.

2. Check for uncommitted work. If found, ask the user
   via AskUserQuestion:
   - **Commit it** — stage and commit before proceeding
   - **Discard it** — `git restore .`
   - **Cancel** — abort the `end` flow

   If `ON_BASE` is true (working directly on the default
   branch), push the commit and skip to step 8 (CI watch).
   Steps 3-7 only apply to feature branches.

3. **Agent review** — use the Task tool to spawn a review
   agent with this prompt:

   > Review the changes on the current branch compared
   > to the default branch. Focus on:
   > 1. Does the code actually address the linked issue
   >    (if any)?
   > 2. Code quality: clarity, edge cases, error handling
   > 3. Test coverage: are the changes tested?
   > 4. Any obvious bugs introduced?
   >
   > Report findings concisely. Do not make changes —
   > report only.

   Use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup`
   output and `git diff <default>..<branch>` as context
   for the review agent.

4. Present the review findings to the user. Ask via
   AskUserQuestion:
   - **Looks good, open PR** — proceed
   - **I'll fix the issues first** — pause the `end`
     flow; user will re-invoke when ready
   - **Open PR anyway** — skip fixes and proceed

5. Determine the linked issue number from the branch
   name (`type/NNN-*`). Build the PR body:

   ```markdown
   ## Summary

   <2-3 sentence description of what was done>

   ## Changes

   - <bulleted list of key changes>

   ## Testing

   <how this was tested or why no tests were needed>
   ```

   If a linked issue exists, append `Resolves #N`
   to the summary.

6. Create the PR:

   ```bash
   DEFAULT=$(bash \
     ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     repo default-branch)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   cat > /tmp/pr-body.md << 'EOF'
   <PR body from step 5>
   EOF
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     pr create \
     --title "<concise PR title>" \
     --head "$BRANCH" \
     --base "$DEFAULT" \
     --body-file /tmp/pr-body.md
   rm -f /tmp/pr-body.md
   ```

7. Confirm to the user: PR URL, linked issue (if any),
   and note that CI is being watched next.

8. **Watch CI** — poll the CI run for the current branch:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     run watch --branch "$BRANCH"
   ```

   Parse the key:value stdout output (`status`, `url`,
   `duration`, `failed_jobs`). Then:
   - **`pass`** — continue to step 8b
   - **`fail`** — show the failed jobs and log excerpt
     (printed to stderr by `run watch`). Ask via
     AskUserQuestion:
     - **Fix it** — pause the `end` flow; user will
       address failures and re-invoke
     - **Ignore** — continue to step 8b
   - **`no-workflow`** — note that no CI workflow was
     found; continue to step 8b
   - **`timeout`** — ask via AskUserQuestion:
     - **Wait longer** — re-run `run watch` with
       `--initial-delay 0` and a longer `--timeout`
     - **Continue** — proceed to step 8b

8a. **Check auto-merge** — only when step 8 returned
   `pass` and `ON_BASE` is false:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     pr auto-merge-status --branch "$CURRENT"
   ```

   Parse the `auto_merge` value from the output.
   If `true`, note to the user that auto-merge is enabled
   and the PR will merge automatically.

8b. **Wait for merge** — skip this step if `ON_BASE` is
   true (direct-to-default pushes have no PR to wait on).
   Otherwise, poll until the PR merges:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-cli \
     pr wait --branch "$CURRENT"
   ```

   Parse the key:value stdout output (`status`,
   `pr_number`, `url`, `duration`). Then:
   - **`merged`** — continue to step 9
   - **`closed`** — ask via AskUserQuestion:
     - **Return to default branch** — continue to step 9
     - **Investigate** — pause the `end` flow for the
       user to investigate
   - **`blocked`** — ask via AskUserQuestion:
     - **Fix conflicts** — pause the `end` flow for the
       user to resolve conflicts and re-invoke
     - **Skip wait** — continue to step 9
   - **`timeout`** — if auto-merge was detected in
     step 8a, automatically re-run `pr wait` with
     `--timeout 600` (up to 2 retries, no prompt).
     If auto-merge was NOT detected, ask via
     AskUserQuestion:
     - **Wait longer** — re-run `pr wait` with a
       longer `--timeout`
     - **Return now** — continue to step 9
   - **`no-pr`** — note that no PR was found;
     continue to step 9

9. **Return to default branch:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch default \
     && git pull
   ```

   Skip if already on the default branch.

10. **Final summary** — present to the user:
    - PR URL (if created)
    - CI status (pass/fail/no-workflow/timeout)
    - Current branch (should be the default branch now)
    - Linked issue (if any)

### Notes

- Do NOT open the PR earlier — PR creation triggers
  CI and merge pipelines
- WIP commits in the branch are fine; squashing is
  optional (not forced)
