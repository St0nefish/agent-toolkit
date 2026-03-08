---
user-invocable: false
name: summarize
description: >-
  Summarize the current repo situation using a tiered context-aware script
  and return a paragraph + categorized file/detail bullets.
allowed-tools: Task, Bash, Read
---

# Summarize

Use one script call as the source of truth, then summarize with an agent.

## Steps

1. Run:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/sitrep
   ```

2. If output says `is_git_repo: false`, report that a summary cannot be generated outside a git repository.

3. Otherwise, invoke the Task tool (`agent_type: general-purpose`) and provide only this script output as input context.

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

- Trust script sections as authoritative (do not run extra git commands unless script fails).
- Include committed + staged + unstaged + untracked file changes when present.
- Group files under 2-5 major categories (examples: "New functionality", "Refactors", "Fixes", "Docs/metadata").
- If output shows `clean: true` with no active branches, return only a short paragraph and no bullet list.
