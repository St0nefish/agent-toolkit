---
user-invocable: false
name: summarize
description: >-
  Summarize the current repo situation using a tiered context-aware snapshot
  and return a paragraph + categorized file/detail bullets.
allowed-tools: Task, Bash, Read
---

# Summarize

Use one direct git snapshot as the source of truth, then summarize with an agent.

## Steps

1. Gather one direct repo snapshot with `git`:
   - whether this is a git repository
   - current branch and default branch
   - clean/dirty state
   - recent commits
   - committed, staged, unstaged, and untracked file lists
   - diff stats or short summaries for each change bucket

2. If the snapshot shows this is not a git repository, report that a summary cannot be generated outside a git repository.

3. Otherwise, invoke the Task tool (`agent_type: general-purpose`) and provide only this snapshot as input context.

4. Return exactly this structure:

   ```text
   <paragraph summarizing the situation>

   * <major change category one summary>
     * <file 1>
       * <file 1 detail 1>
       * <file 1 detail 2>
     * <file 2>
       * <file 2 detail 1>
       * <file 2 detail 2>
   * <major change category two summary>
     * <file 3>
       * <file 3 detail 1>
   ```

## Rules

- Trust the initial snapshot as authoritative (do not keep running extra git commands once it is collected).
- Include committed + staged + unstaged + untracked file changes when present.
- Group files under 2-5 major categories (examples: "New functionality", "Refactors", "Fixes", "Docs/metadata").
- If the snapshot shows a clean repo with no relevant in-flight work, return only a short paragraph and no bullet list.
