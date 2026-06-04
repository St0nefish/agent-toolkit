---
description: "Review, clean up, and open a PR to finalize the work"
allowed-tools: Bash, Read, AskUserQuestion, Task
---

Finalize the work: review, clean up commits, push, open a PR,
watch CI, and return to the default branch.

### Steps

1. Gather current state:
   inspect the current repo directly with `git`:

   - `CURRENT` — the current branch name
   - `DEFAULT` — the default branch name (prefer `origin/HEAD`; fall back to `main` or `master`)
   - `ON_BASE` — true if the current branch is the default branch with no diverging commits
   - uncommitted changes
   - commits ahead of the default branch

   If `ON_BASE` is true and there are no uncommitted changes, tell the user there is nothing to finalize and stop.

1b. Check for an existing open PR for the current branch:

- on GitHub repos, prefer `gh pr list --head "$CURRENT" --state open --json number,url,headRefName`
- otherwise use the equivalent host-native PR listing command if available

   If found, extract the PR URL and number, skip steps 3-7, and jump directly to step 8 (CI watch) using the existing PR info.

2. Check for uncommitted work. If found, ask the user via AskUserQuestion:
   - **Commit it** — stage and commit before proceeding
   - **Discard it** — `git restore .`
   - **Cancel** — abort the `end` flow

   If `ON_BASE` is true (working directly on the default branch), ask before pushing, then skip to step 8 (CI watch). Steps 3-7 only apply to feature branches.

3. **Agent review** — use the Task tool to spawn a review agent with this prompt:

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

   Use the direct git state from step 1 plus `git diff <default>..<branch>` as context for the review agent.

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
   - on GitHub repos, prefer `gh pr create` with the title, base branch, head branch, and PR body from step 5
   - otherwise use the equivalent host-native PR creation command if available
   - ask before pushing if the branch is not yet on the remote

7. Confirm to the user: PR URL, linked issue (if any), and note that CI is being watched next.

8. **Watch CI** — poll the CI run for the current branch:
   - on GitHub repos, prefer `gh pr checks --watch` for the PR created or found above
   - otherwise use the equivalent host-native CI status command if available
   - normalize the result into `pass`, `fail`, `no-workflow`, or `timeout`, then:
     - **`pass`** — continue to step 8b
     - **`fail`** — show the failed jobs and log excerpt if available. Ask via AskUserQuestion:
       - **Fix it** — pause the `end` flow; user will address failures and re-invoke
       - **Ignore** — continue to step 8b
     - **`no-workflow`** — note that no CI workflow was found; continue to step 8b
     - **`timeout`** — ask via AskUserQuestion:
       - **Wait longer** — keep watching
       - **Continue** — proceed to step 8b

8a. **Check auto-merge** — only when step 8 returned `pass` and `ON_BASE` is false:
   inspect the PR directly (for example with `gh pr view --json autoMergeRequest,state,mergeStateStatus`)
   and parse whether auto-merge is enabled.
   If `true`, note to the user that auto-merge is enabled and the PR will merge automatically.

8b. **Wait for merge** — skip this step if `ON_BASE` is true (direct-to-default pushes have no PR to wait on). Otherwise, poll until the PR merges:
   inspect the PR directly (for example with `gh pr view --json state,mergedAt,url,number`)
   until it merges, closes, blocks, times out, or the user chooses to stop waiting.
   Normalize the result into `merged`, `closed`, `blocked`, `timeout`, or `no-pr`, then:

- **`merged`** — continue to step 9
- **`closed`** — ask via AskUserQuestion:
  - **Return to default branch** — continue to step 9
  - **Investigate** — pause the `end` flow for the user to investigate
- **`blocked`** — ask via AskUserQuestion:
  - **Fix conflicts** — pause the `end` flow for the user to resolve conflicts and re-invoke
  - **Skip wait** — continue to step 9
- **`timeout`** — ask via AskUserQuestion whether to keep waiting or return now
- **`no-pr`** — note that no PR was found; continue to step 9

9. **Return to the main checkout / default branch:**

   If you worked in a worktree (under `.github/worktrees/`) and the PR merged, tear it down first with the `git-worktree` extension's `sf_git_worktree_remove` tool (or the equivalent direct `git worktree remove .github/worktrees/<slug>` flow), then `git branch -d <branch>` (use `--force`/`-D` only for a dirty or unmerged branch the user agrees to discard). If the PR did **not** merge, leave the worktree in place. Then switch to the default branch in the main checkout:

   ```bash
   git switch "$DEFAULT" && git pull --ff-only
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
- Use direct `git`/`gh` commands rather than plugin helper-script paths; Copilot
  CLI does not guarantee plugin-root environment variables inside Bash tool invocations.
