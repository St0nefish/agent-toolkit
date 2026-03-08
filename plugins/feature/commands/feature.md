---
description: "Feature workflow — start, issue, resume, checkpoint, handoff, end, status, catchup"
argument-hint: "[action]"
allowed-tools: Bash, Read, AskUserQuestion, Task
disable-model-invocation: true
---

# Feature Workflow

$IF($1, Run the **$1** action below.)
$IF(!$1, Available actions: `start`, `issue`, `resume`, `checkpoint`, `handoff`, `end`, `status`, `catchup`. Usage: `/feature [action]`)

State lives in git branches, commits, and the issue tracker — no local session files.

---

## start

Generic entry point. Shows available work and lets the user pick what to focus on.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Collect the two sources of available work:

   **Open issues** (unstarted work):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue list --limit 20 --state open
   ```

   **Active branches** (in-progress work) — branches not yet merged to the default branch:

   ```bash
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools repo default-branch)
   git --no-pager branch --no-merged "$DEFAULT" --format '%(refname:short)' 2>/dev/null
   ```

3. **Present the options.** Build a numbered list combining both sources:
   - Issues displayed as: `[issue] #N — <title>` (show at most 10)
   - Branches displayed as: `[branch] <branch>` (show at most 5)
   - Always include a final option: `[new] Describe what you want to work on`

   Use AskUserQuestion with this combined list as choices.

4. **Act on the selection:**

   - **Issue selected** — follow the `issue` action from step 3 onward (branch creation), skipping the list/pick steps
   - **Branch selected** — follow the `resume` action from step 2 onward (context extraction), skipping the list/pick step
   - **Freeform selected** — ask the user to describe the task, then:
     - Create a `wip/<kebab-slug>` branch: `git checkout -b wip/<slug>`
     - No issue is linked; proceed with free-form task description as context

5. Confirm the starting context to the user:
   - Branch name (new or existing)
   - Linked issue number and title (if any)
   - First suggested steps based on context

---

## issue

Select an open issue and begin work on it.

### Steps

1. Fetch open issues:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue list --limit 20 --state open
   ```

2. **Rank and select.** From the returned JSON array, pick the top 3 by priority:
   - Labels indicating urgency: `critical`, `blocker`, `high-priority`, `bug` rank higher
   - Issues with a milestone set rank higher than those without
   - More comments → higher priority (community signal)
   - Older issues rank higher than newer (age as proxy for neglect)

   Display the top 3 as choices and use AskUserQuestion. Include issue number, title, and labels for each choice.

3. Fetch the full issue:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N>
   ```

4. **Determine branch type** from issue labels:
   - `bug`, `fix` → `bug/`
   - `enhancement`, `feature`, `improvement` → `enhancement/`
   - `docs`, `chore`, `refactor`, `maintenance` → `chore/`
   - No matching label → `feature/`

5. **Create the branch.** Generate a kebab-case slug (3-5 words) from the issue title:

   ```bash
   git checkout -b <type>/<N>-<slug>
   ```

   Example: issue #42 "Fix login crash on empty password" → `bug/42-fix-login-crash`

6. Confirm to the user:
   - Branch created
   - Issue title and body summary
   - Suggested first implementation steps based on the issue description

---

## resume

Resume work on an existing in-progress branch.

### Steps

1. List active branches (not merged to default):

   ```bash
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools repo default-branch)
   git --no-pager branch --no-merged "$DEFAULT" --format '%(refname:short)' 2>/dev/null
   ```

2. If more than one branch exists, use AskUserQuestion to let the user pick. If only one, proceed with it automatically.

3. Check out the selected branch if not already on it:

   ```bash
   git checkout <branch>
   ```

4. Gather context from multiple sources in parallel:

   ```bash
   # Full state dump
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

   **If the branch name matches `type/NNN-*`**, extract the issue number and fetch it:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N>
   ```

   **Check for a WIP/handoff commit** — search recent commits for one with `=== IN PROGRESS ===` in the body:

   ```bash
   git --no-pager log --max-count=5 --format="%H %s" | grep -i "^[^ ]* WIP:"
   ```

   If found, extract the body: `git --no-pager show <sha> --format=%B --no-patch`

5. Build and present the resume context:
   - **Branch:** name, commits ahead of default, uncommitted changes
   - **Linked issue:** title, body excerpt, recent comments (if any)
   - **In progress** (from WIP commit `=== IN PROGRESS ===` section, if present)
   - **Next steps** (from WIP commit `=== NEXT STEPS ===` section or last issue comment, if present)
   - **Key context** (from WIP commit `=== KEY CONTEXT ===` section, if present)
   - **Recent commits:** last 3 subjects

6. Suggest the most logical next action based on the context. Ask the user if they want to proceed or adjust the plan.

---

## checkpoint

PROACTIVELY invoke this (without being asked) after completing a major task, stage, or milestone, or when context window usage is approaching full.

Commits staged/unstaged changes and posts structured context to the linked issue.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Infer what's in progress and what should come next from conversation context. When auto-triggering, do NOT ask — infer from the conversation. Only use AskUserQuestion if explicitly invoked and progress is genuinely unclear.

3. Compose the checkpoint comment content with these sections:

   ```
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
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue comment <N> --body-file /tmp/checkpoint-comment.md
   rm -f /tmp/checkpoint-comment.md
   ```

6. Briefly confirm: checkpoint committed and (if applicable) posted to issue #N. When auto-triggering, keep to one line. When user-invoked, mention `/feature resume` to continue from this point.

---

## handoff

Commit all work, push, and record handoff context on the linked issue for cross-machine pickup.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Based on catchup output and conversation context, construct the handoff content:

   **WIP commit body** (what changed — lives in git history):

   ```
   === IN PROGRESS ===
   - <current state of work, partial implementations, files touched>
   ```

   **Issue comment** (what to do next — lives on the issue, accessible without cloning):

   ```
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
   ```

   Substitute all template values with actual content before executing. If `git push` fails, the commit still exists locally — inform the user to push manually.

4. If the current branch matches `type/NNN-*`, post the handoff comment to the linked issue:

   ```bash
   cat > /tmp/handoff-comment.md << 'EOF'
   <issue comment content from step 2>
   EOF
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue comment <N> --body-file /tmp/handoff-comment.md
   rm -f /tmp/handoff-comment.md
   ```

5. Confirm to the user:
   - Branch pushed
   - Issue #N updated with handoff context (if applicable)
   - How to resume: `git pull && /feature resume` on the other machine

### Notes

- The WIP commit is a normal commit — continue working on top of it, no soft-reset needed
- If no issue is linked, context lives only in the WIP commit; instruct the user to run `/feature resume` on the other machine

---

## end

Finalize the feature: review, clean up commits, push, and open a PR.

### Steps

1. Gather current state:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. Check for uncommitted work. If found, ask the user via AskUserQuestion:
   - **Commit it** — stage and commit before proceeding
   - **Discard it** — `git checkout -- .`
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
   DEFAULT=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools repo default-branch)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   cat > /tmp/pr-body.md << 'EOF'
   <PR body from step 5>
   EOF
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools pr create \
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

---

## status

Lightweight check of the current work context.

### Steps

1. Run catchup:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. From the output, extract and present a concise status card:

   ```
   Branch: <branch>
   Commits ahead of <default>: <N>
   Linked issue: #N — <title> (if branch matches type/NNN-*)
   Uncommitted changes: <none | N files>
   Recent commits: <last 3 subjects>
   ```

3. If the branch matches `type/NNN-*`, fetch just the issue title (no full body):

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N> | jq -r '"#\(.number) — \(.title) [\(.state)]"'
   ```

4. **Do not read changed files or rebuild context.** This is intentionally lightweight. Point the user to `/feature resume` or `/feature catchup` for full context.

---

## catchup

Rebuild full context of in-progress work. Use after switching context or starting a new session.

### Steps

1. Run the catchup script:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/catchup
   ```

2. If the current branch matches `type/NNN-*`, fetch the full issue and recent comments:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/git-tools issue show <N>
   ```

3. Read changed files (from both committed and uncommitted changes in the catchup output). If more than 15 files, prioritize:
   - Source code over generated/lock files
   - Files mentioned in recent commit messages
   - Test files alongside their implementations

4. Present a concise summary:
   - **Branch:** name and commits ahead of default
   - **Linked issue:** #N title, key requirements from body (if any)
   - **What's been done:** from recent commits
   - **What's in progress:** uncommitted changes, any WIP commit context
   - **Key files:** most important changed files
   - **Suggested next steps:** from issue, recent commits, or partial work

### Notes

- Read-only, safe for auto-approval
- Sections with no content are omitted to keep output lean
